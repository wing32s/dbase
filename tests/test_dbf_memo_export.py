"""
Test file for DBF memo export and import functionality.
This tests exporting memos to text and re-importing them.
"""

import os
import shutil
import unittest
from dbf_module import (
    DBFColumn, DBFHeader,
    dbf_file_create, dbf_file_close, dbf_file_open,
    dbf_file_append_row, dbf_file_read_row, dbf_file_seek_to_row,
    dbf_file_set_row_deleted, dbf_file_get_field_str, dbf_file_set_field_str,
    dbf_file_write_row, dbf_file_clear_memo_fields, dbf_file_get_actual_row_count,
    export_dbf_to_text, import_dbf_from_text,
    export_dbf_memos_to_text, import_dbf_memos_from_text, import_dbf_memos_from_text_ex,
    compact_dbf,
    dbf_memo_write, dbf_memo_write_buffer, dbf_memo_read_small
)


def init_test_header():
    """Initialize a test header with all field types including memo."""
    fields = [
        DBFColumn(name="TEXT", field_type="C", length=10, decimals=0),
        DBFColumn(name="NUMBER", field_type="N", length=3, decimals=0),
        DBFColumn(name="DECIMAL", field_type="N", length=4, decimals=1),
        DBFColumn(name="FLAG", field_type="L", length=1, decimals=0),
        DBFColumn(name="DATE", field_type="D", length=8, decimals=0),
        DBFColumn(name="MEMO", field_type="M", length=10, decimals=0)
    ]
    
    header = DBFHeader()
    header.fields = fields
    header.field_count = len(fields)
    
    return header


def prep_test_database_for_export(filename: str):
    """
    Prepare test database for export by:
    1. Adding a binary memo for row 2 (CHARLIE)
    2. Updating row 2 with the new memo block number
    3. Deleting row 0 (ALPHA)
    
    This prepares the database so we can verify that:
    - Binary memos are exported correctly
    - Deleted rows are skipped during export
    """
    # Open the DBF file
    dbf = dbf_file_open(filename + '.DBF')
    
    # Add a binary memo for row 2
    bin_data = bytes([0x00, 0x01, 0x7F, 0x80, 0xFF, 0x10, 0x20, 0x30])
    bin_block = dbf_memo_write_buffer(filename + '.DBT', 2, bin_data)
    
    # Update row 2 with the new memo block number
    dbf_file_seek_to_row(dbf, 2)
    row = dbf_file_read_row(dbf)
    dbf_file_set_field_str(row, dbf, 6, str(bin_block))
    
    # Build values array and write back
    values = ['']  # Index 0 is ignored
    for i in range(1, 7):
        values.append(dbf_file_get_field_str(row, dbf, i))
    
    dbf_file_seek_to_row(dbf, 2)
    dbf_file_write_row(dbf, values)
    
    # Delete row 0
    dbf_file_set_row_deleted(dbf, 0, True)
    
    # Close the file
    dbf_file_close(dbf)


class TestDBFMemoExport(unittest.TestCase):
    """Test cases for DBF memo export and import."""
    
    def setUp(self):
        """Set up test environment."""
        self.test_files = []
        self.test_filename = "test_memo_export"
        
    def tearDown(self):
        """Clean up test files."""
        # Clean up specific test files
        for ext in ['.DBF', '.DBT', '.TXT', '.MEM']:
            if os.path.exists(self.test_filename + ext):
                try:
                    os.remove(self.test_filename + ext)
                except:
                    pass
        
        # Clean up any other test files
        for filename in self.test_files:
            for ext in ['.DBF', '.DBT', '.TXT', '.MEM']:
                full_path = filename + ext
                if os.path.exists(full_path):
                    try:
                        os.remove(full_path)
                    except:
                        pass
    
    def create_test_database(self):
        """Create a test database with 4 rows (3 with memos, 1 without)."""
        header = init_test_header()
        dbf = dbf_file_create(self.test_filename, header)
        
        # Row 0: ALPHA with memo
        memo1 = dbf_memo_write(self.test_filename + ".DBT", 1, "Memo alpha")
        row1 = ['', 'ALPHA', '1', '2.2', 'T', '20240115', str(memo1)]
        dbf_file_append_row(dbf, row1)
        
        # Row 1: BRAVO with memo
        memo2 = dbf_memo_write(self.test_filename + ".DBT", 1, "Memo bravo")
        row2 = ['', 'BRAVO', '33', '4.4', 'F', '20240216', str(memo2)]
        dbf_file_append_row(dbf, row2)
        
        # Row 2: CHARLIE with memo
        memo3 = dbf_memo_write(self.test_filename + ".DBT", 1, "Memo charlie")
        row3 = ['', 'CHARLIE', '555', '16.6', 'T', '20240317', str(memo3)]
        dbf_file_append_row(dbf, row3)
        
        # Row 3: DELTA without memo
        row4 = ['', 'DELTA', '7', '0.7', 'F', '20240418', '0']
        dbf_file_append_row(dbf, row4)
        
        dbf_file_close(dbf)
    
    def test_prep_database_for_export(self):
        """Test preparing database for export."""
        # Create test database
        self.create_test_database()
        
        # Prep for export
        prep_test_database_for_export(self.test_filename)
        
        # Verify changes
        dbf = dbf_file_open(self.test_filename + '.DBF')
        
        # Row 0 should be deleted
        dbf_file_seek_to_row(dbf, 0)
        row = dbf_file_read_row(dbf)
        self.assertEqual(row[0], '*', "Row 0 should be deleted")
        
        # Row 2 should have a binary memo
        dbf_file_seek_to_row(dbf, 2)
        row = dbf_file_read_row(dbf)
        memo_block = int(row[6].strip())
        self.assertGreater(memo_block, 0, "Row 2 should have a memo")
        
        # Verify binary memo content
        memo_type, memo_data = dbf_memo_read_small(self.test_filename + '.DBT', memo_block)
        expected = bytes([0x00, 0x01, 0x7F, 0x80, 0xFF, 0x10, 0x20, 0x30])
        # For binary memos (type 2), data should be bytes
        self.assertEqual(memo_type, 2, "Should be binary memo")
        self.assertEqual(memo_data, expected, "Binary memo should match")
        
        dbf_file_close(dbf)
    
    def test_memo_export_skips_deleted(self):
        """Test that memo export skips deleted rows."""
        # Create and prep database
        self.create_test_database()
        prep_test_database_for_export(self.test_filename)
        
        # Export memos
        export_dbf_memos_to_text(self.test_filename)
        
        # Read the .MEM file
        with open(self.test_filename + '.MEM', 'r') as f:
            lines = f.readlines()
        
        # Should have 2 lines (row 1 BRAVO and row 2 CHARLIE)
        # Row 0 (ALPHA) is deleted, row 3 (DELTA) has no memo
        self.assertEqual(len(lines), 2, "Should have 2 memo export lines")
        
        # Parse the lines to check content
        export_indices = []
        for line in lines:
            parts = line.strip().split('|')
            if len(parts) >= 2:
                export_indices.append(int(parts[0]))
        
        # Export indices should be 0 and 1 (BRAVO and CHARLIE, skipping deleted ALPHA)
        self.assertEqual(export_indices, [0, 1], "Export indices should be 0 and 1")
        
        # Verify the lines are for field 6 (memo field)
        for line in lines:
            parts = line.strip().split('|')
            self.assertEqual(int(parts[1]), 6, "Should be field 6 (memo field)")
    
    def test_memo_export_import_roundtrip(self):
        """Test full memo export/import roundtrip."""
        # Create and prep database
        self.create_test_database()
        prep_test_database_for_export(self.test_filename)
        
        # Export structure and data
        export_dbf_to_text(self.test_filename)
        
        # Export memos
        export_dbf_memos_to_text(self.test_filename)
        
        # Import to new file
        import_filename = "test_memo_import"
        self.test_files.append(import_filename)
        
        # Copy text files
        shutil.copy(self.test_filename + '.TXT', import_filename + '.TXT')
        shutil.copy(self.test_filename + '.MEM', import_filename + '.MEM')
        
        # Import structure and data
        import_dbf_from_text(import_filename)
        
        # Clear memo fields before importing memos
        dbf = dbf_file_open(import_filename + '.DBF')
        dbf_file_clear_memo_fields(dbf)
        dbf_file_close(dbf)
        
        # Import memos
        import_dbf_memos_from_text(import_filename)
        
        # Verify imported data
        dbf = dbf_file_open(import_filename + '.DBF')
        
        # Row 0 (BRAVO - was row 1, now row 0 after skipping deleted)
        dbf_file_seek_to_row(dbf, 0)
        row = dbf_file_read_row(dbf)
        self.assertEqual(row[1].strip(), 'BRAVO')
        memo_block = int(row[6].strip())
        self.assertGreater(memo_block, 0)
        _, memo_text = dbf_memo_read_small(import_filename + '.DBT', memo_block)
        self.assertEqual(memo_text, 'Memo bravo')
        
        # Row 1 (CHARLIE - was row 2, now row 1)
        dbf_file_seek_to_row(dbf, 1)
        row = dbf_file_read_row(dbf)
        self.assertEqual(row[1].strip(), 'CHARLIE')
        memo_block = int(row[6].strip())
        self.assertGreater(memo_block, 0)
        # This should be the binary memo
        memo_type, memo_data = dbf_memo_read_small(import_filename + '.DBT', memo_block)
        expected = bytes([0x00, 0x01, 0x7F, 0x80, 0xFF, 0x10, 0x20, 0x30])
        self.assertEqual(memo_type, 2, "Should be binary memo")
        self.assertEqual(memo_data, expected)
        
        # Row 2 (DELTA - no memo)
        dbf_file_seek_to_row(dbf, 2)
        row = dbf_file_read_row(dbf)
        self.assertEqual(row[1].strip(), 'DELTA')
        self.assertEqual(row[6].strip(), '0')
        
        dbf_file_close(dbf)
    
    def test_clear_memo_fields(self):
        """Test clearing all memo fields."""
        # Create test database
        self.create_test_database()
        
        # Verify memos exist
        dbf = dbf_file_open(self.test_filename + '.DBF')
        dbf_file_seek_to_row(dbf, 0)
        row = dbf_file_read_row(dbf)
        memo_block = int(row[6].strip())
        self.assertGreater(memo_block, 0, "Should have memo before clear")
        dbf_file_close(dbf)
        
        # Clear memo fields
        dbf = dbf_file_open(self.test_filename + '.DBF')
        dbf_file_clear_memo_fields(dbf)
        dbf_file_close(dbf)
        
        # Verify all memos are cleared
        dbf = dbf_file_open(self.test_filename + '.DBF')
        for row_idx in range(4):
            dbf_file_seek_to_row(dbf, row_idx)
            row = dbf_file_read_row(dbf)
            memo_field = row[6].strip()
            self.assertEqual(memo_field, '0', f"Row {row_idx} memo should be cleared")
        dbf_file_close(dbf)
    
    def test_memo_export_import_preserve_blocks(self):
        """Test memo export/import with block number preservation."""
        # Create and prep database
        self.create_test_database()
        prep_test_database_for_export(self.test_filename)
        
        # Export structure and memos
        export_dbf_to_text(self.test_filename)
        export_dbf_memos_to_text(self.test_filename)
        
        # Read .MEM file to get original block numbers
        with open(self.test_filename + '.MEM', 'r') as f:
            lines = f.readlines()
        
        # Parse block numbers by row
        block_by_row = {}
        for line in lines:
            parts = line.strip().split('|')
            if len(parts) >= 4:
                row_idx = int(parts[0])
                field_idx = int(parts[1])
                block_num = int(parts[3])
                if field_idx == 6:  # Memo field
                    block_by_row[row_idx] = block_num
        
        # Should have blocks for rows 0 and 1 (BRAVO and CHARLIE)
        self.assertIn(0, block_by_row, "Row 0 should have memo")
        self.assertIn(1, block_by_row, "Row 1 should have memo")
        
        # Import to new file
        import_filename = "test_memo_preserve"
        self.test_files.append(import_filename)
        
        shutil.copy(self.test_filename + '.TXT', import_filename + '.TXT')
        shutil.copy(self.test_filename + '.MEM', import_filename + '.MEM')
        
        # Import structure
        import_dbf_from_text(import_filename)
        
        # Import memos with preserve_blocks=True
        import_dbf_memos_from_text_ex(import_filename, preserve_blocks=True)
        
        # Verify block numbers are preserved
        dbf = dbf_file_open(import_filename + '.DBF')
        
        # Row 0 should have same block number
        dbf_file_seek_to_row(dbf, 0)
        row = dbf_file_read_row(dbf)
        memo_block = int(row[6].strip())
        self.assertEqual(memo_block, block_by_row[0], "Row 0 block should be preserved")
        
        # Row 1 should have same block number
        dbf_file_seek_to_row(dbf, 1)
        row = dbf_file_read_row(dbf)
        memo_block = int(row[6].strip())
        self.assertEqual(memo_block, block_by_row[1], "Row 1 block should be preserved")
        
        # Verify memo content is still correct
        dbf_file_seek_to_row(dbf, 0)
        row = dbf_file_read_row(dbf)
        memo_block = int(row[6].strip())
        _, memo_text = dbf_memo_read_small(import_filename + '.DBT', memo_block)
        self.assertEqual(memo_text, 'Memo bravo')
        
        dbf_file_close(dbf)
    
    def test_compact_dbf(self):
        """Test compacting DBF by removing deleted rows and compacting memos."""
        # Create and prep database (deletes row 0 ALPHA, has binary memo in row 2)
        self.create_test_database()
        prep_test_database_for_export(self.test_filename)
        
        # Compact to new file
        compact_filename = "test_compact"
        self.test_files.append(compact_filename)
        
        compact_dbf(self.test_filename, compact_filename)
        
        # Open compacted file
        dbf = dbf_file_open(compact_filename + '.DBF')
        
        # Should have 3 rows (BRAVO, CHARLIE, DELTA - ALPHA was deleted)
        row_count = dbf_file_get_actual_row_count(dbf)
        self.assertEqual(row_count, 3, "Compacted file should have 3 rows")
        
        # Row 0: BRAVO (was row 1, now row 0)
        dbf_file_seek_to_row(dbf, 0)
        row = dbf_file_read_row(dbf)
        self.assertEqual(row[1].strip(), 'BRAVO', "Row 0 should be BRAVO")
        memo_block = int(row[6].strip())
        self.assertGreater(memo_block, 0, "BRAVO should have memo")
        _, memo_text = dbf_memo_read_small(compact_filename + '.DBT', memo_block)
        self.assertEqual(memo_text, 'Memo bravo', "BRAVO memo should be preserved")
        
        # Row 1: CHARLIE (was row 2, now row 1) - has binary memo
        dbf_file_seek_to_row(dbf, 1)
        row = dbf_file_read_row(dbf)
        self.assertEqual(row[1].strip(), 'CHARLIE', "Row 1 should be CHARLIE")
        memo_block = int(row[6].strip())
        self.assertGreater(memo_block, 0, "CHARLIE should have memo")
        memo_type, memo_data = dbf_memo_read_small(compact_filename + '.DBT', memo_block)
        expected = bytes([0x00, 0x01, 0x7F, 0x80, 0xFF, 0x10, 0x20, 0x30])
        self.assertEqual(memo_type, 2, "Should be binary memo")
        self.assertEqual(memo_data, expected, "Binary memo should be preserved")
        
        # Row 2: DELTA (was row 3, now row 2) - no memo
        dbf_file_seek_to_row(dbf, 2)
        row = dbf_file_read_row(dbf)
        self.assertEqual(row[1].strip(), 'DELTA', "Row 2 should be DELTA")
        self.assertEqual(row[6].strip(), '0', "DELTA should have no memo")
        
        # Verify no deleted rows
        for row_idx in range(row_count):
            dbf_file_seek_to_row(dbf, row_idx)
            row = dbf_file_read_row(dbf)
            self.assertNotEqual(row[0], '*', f"Row {row_idx} should not be deleted")
        
        dbf_file_close(dbf)


if __name__ == "__main__":
    unittest.main()
