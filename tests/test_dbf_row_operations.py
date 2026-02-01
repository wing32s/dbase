"""
Test file for DBF row operations (append, read, seek).
Tests all field types: Character, Number, Decimal, Logical, Date, and Memo.
"""

import os
import unittest
from dbf_module import (
    DBFColumn, DBFHeader, DBFFile,
    dbf_file_create, dbf_file_close, dbf_file_open,
    dbf_file_append_row, dbf_file_read_row, dbf_file_write_row, dbf_file_seek_to_row,
    dbf_file_seek_to_first_row, dbf_file_get_actual_row_count,
    dbf_file_set_row_deleted, dbf_file_get_field_str, dbf_file_set_field_str,
    dbf_memo_write, dbf_memo_read_small, trim_string,
    DBF_LANG_US
)


def init_test_header() -> DBFHeader:
    """
    Initialize test header with all field types.
    Matches the Pascal InitTestHeader function.
    """
    header = DBFHeader()
    header.version = 0x05  # dBase V with memo
    header.table_flags = 0
    header.language_driver = DBF_LANG_US
    header.field_count = 6
    
    # Field 1: TEXT - Character(10)
    header.fields.append(DBFColumn(name="TEXT", field_type="C", length=10, decimals=0))
    
    # Field 2: NUMBER - Numeric(3)
    header.fields.append(DBFColumn(name="NUMBER", field_type="N", length=3, decimals=0))
    
    # Field 3: DECIMAL - Numeric(4, 1)
    header.fields.append(DBFColumn(name="DECIMAL", field_type="N", length=4, decimals=1))
    
    # Field 4: FLAG - Logical(1)
    header.fields.append(DBFColumn(name="FLAG", field_type="L", length=1, decimals=0))
    
    # Field 5: DATE - Date(8)
    header.fields.append(DBFColumn(name="DATE", field_type="D", length=8, decimals=0))
    
    # Field 6: MEMO - Memo(2) - stores block number
    header.fields.append(DBFColumn(name="MEMO", field_type="M", length=2, decimals=0))
    
    return header


class TestDBFRowOperations(unittest.TestCase):
    """Test cases for DBF row operations."""
    
    def setUp(self):
        """Set up test environment."""
        self.test_files = []
        self.test_filename = "test_rows"
        
    def tearDown(self):
        """Clean up test files."""
        for filename in self.test_files:
            # Remove DBF file
            if os.path.exists(filename):
                try:
                    os.remove(filename)
                except:
                    pass
            
            # Remove DBT file
            dbt_file = filename.replace('.DBF', '.DBT')
            if os.path.exists(dbt_file):
                try:
                    os.remove(dbt_file)
                except:
                    pass
    
    def test_row_append_one(self):
        """Test appending one row with all field types (matches TestRowAppendOne)."""
        # Create database
        header = init_test_header()
        dbf = dbf_file_create(self.test_filename, header)
        
        # Add to cleanup
        self.test_files.append(self.test_filename + ".DBF")
        
        # Write memo
        memo_text = "Memo alpha"
        memo_block = dbf_memo_write(self.test_filename + ".DBT", 1, memo_text)
        self.assertGreater(memo_block, 0)
        
        # Prepare row values (1-indexed, values[0] is ignored)
        values = [
            '',           # 0: ignored
            'ALPHA',      # 1: TEXT
            '1',          # 2: NUMBER
            '2.2',        # 3: DECIMAL
            'T',          # 4: FLAG
            '20240115',   # 5: DATE
            str(memo_block)  # 6: MEMO
        ]
        
        # Append row
        dbf_file_append_row(dbf, values)
        
        # Seek to first row and read
        dbf_file_seek_to_row(dbf, 0)
        row = dbf_file_read_row(dbf)
        
        # Verify row values
        self.assertEqual(row[0], ' ')  # Not deleted
        self.assertEqual(row[1].strip(), 'ALPHA')
        self.assertEqual(row[2].strip(), '1')
        self.assertEqual(row[3].strip(), '2.2')
        self.assertEqual(row[4].strip(), 'T')
        self.assertEqual(row[5].strip(), '20240115')
        self.assertEqual(row[6].strip(), str(memo_block))
        
        # Verify memo
        memo_type, read_memo = dbf_memo_read_small(self.test_filename + ".DBT", memo_block)
        self.assertEqual(memo_type, 1)
        self.assertEqual(read_memo, memo_text)
        
        # Close file
        dbf_file_close(dbf)
    
    def test_row_append_multiple(self):
        """Test appending multiple rows (matches TestRowAppend with 4 rows)."""
        # Create database
        header = init_test_header()
        dbf = dbf_file_create(self.test_filename, header)
        
        # Add to cleanup
        self.test_files.append(self.test_filename + ".DBF")
        
        # Row 1: ALPHA with memo
        memo1_text = "Memo alpha"
        memo1_block = dbf_memo_write(self.test_filename + ".DBT", 1, memo1_text)
        values1 = ['', 'ALPHA', '1', '2.2', 'T', '20240115', str(memo1_block)]
        dbf_file_append_row(dbf, values1)
        
        # Row 2: BRAVO with memo
        memo2_text = "Memo bravo"
        memo2_block = dbf_memo_write(self.test_filename + ".DBT", 1, memo2_text)
        values2 = ['', 'BRAVO', '33', '4.4', 'F', '20240216', str(memo2_block)]
        dbf_file_append_row(dbf, values2)
        
        # Row 3: CHARLIE with memo
        memo3_text = "Memo charlie"
        memo3_block = dbf_memo_write(self.test_filename + ".DBT", 1, memo3_text)
        values3 = ['', 'CHARLIE', '555', '16.6', 'T', '20240317', str(memo3_block)]
        dbf_file_append_row(dbf, values3)
        
        # Row 4: DELTA without memo (memo block = 0)
        values4 = ['', 'DELTA', '7', '0.7', 'F', '20240418', '0']
        dbf_file_append_row(dbf, values4)
        
        # Verify row 1
        dbf_file_seek_to_row(dbf, 0)
        row1 = dbf_file_read_row(dbf)
        self.assertEqual(row1[1].strip(), 'ALPHA')
        self.assertEqual(row1[2].strip(), '1')
        self.assertEqual(row1[3].strip(), '2.2')
        self.assertEqual(row1[4].strip(), 'T')
        self.assertEqual(row1[5].strip(), '20240115')
        self.assertEqual(row1[6].strip(), str(memo1_block))
        
        # Verify row 2
        dbf_file_seek_to_row(dbf, 1)
        row2 = dbf_file_read_row(dbf)
        self.assertEqual(row2[1].strip(), 'BRAVO')
        self.assertEqual(row2[2].strip(), '33')
        self.assertEqual(row2[3].strip(), '4.4')
        self.assertEqual(row2[4].strip(), 'F')
        self.assertEqual(row2[5].strip(), '20240216')
        self.assertEqual(row2[6].strip(), str(memo2_block))
        
        # Verify row 3
        dbf_file_seek_to_row(dbf, 2)
        row3 = dbf_file_read_row(dbf)
        self.assertEqual(row3[1].strip(), 'CHARLIE')
        self.assertEqual(row3[2].strip(), '555')
        self.assertEqual(row3[3].strip(), '16.6')
        self.assertEqual(row3[4].strip(), 'T')
        self.assertEqual(row3[5].strip(), '20240317')
        self.assertEqual(row3[6].strip(), str(memo3_block))
        
        # Row 4: DELTA without memo
        dbf_file_seek_to_row(dbf, 3)
        row4 = dbf_file_read_row(dbf)
        self.assertEqual(row4[1].strip(), 'DELTA')
        self.assertEqual(row4[2].strip(), '7')
        self.assertEqual(row4[3].strip(), '0.7')
        self.assertEqual(row4[4].strip(), 'F')
        self.assertEqual(row4[5].strip(), '20240418')
        self.assertEqual(row4[6].strip(), '0')  # No memo
        
        # Verify memos exist
        _, memo1 = dbf_memo_read_small(self.test_filename + ".DBT", memo1_block)
        self.assertEqual(memo1, memo1_text)
        
        _, memo2 = dbf_memo_read_small(self.test_filename + ".DBT", memo2_block)
        self.assertEqual(memo2, memo2_text)
        
        _, memo3 = dbf_memo_read_small(self.test_filename + ".DBT", memo3_block)
        self.assertEqual(memo3, memo3_text)
        
        # Verify row 4 has no memo (block 0 should return empty)
        memo_type4, memo4 = dbf_memo_read_small(self.test_filename + ".DBT", 0)
        self.assertEqual(memo_type4, 0)
        self.assertEqual(memo4, '')
        
        # Close file
        dbf_file_close(dbf)
    
    def test_row_seek(self):
        """Test seeking to rows in random order (matches TestRowSeek)."""
        # Create database and add 4 rows
        header = init_test_header()
        dbf = dbf_file_create(self.test_filename, header)
        
        # Add to cleanup
        self.test_files.append(self.test_filename + ".DBF")
        
        # Add the same 4 rows as in test_row_append_multiple
        # Row 1: ALPHA with memo
        memo1_text = "Memo alpha"
        memo1_block = dbf_memo_write(self.test_filename + ".DBT", 1, memo1_text)
        values1 = ['', 'ALPHA', '1', '2.2', 'T', '20240115', str(memo1_block)]
        dbf_file_append_row(dbf, values1)
        
        # Row 2: BRAVO with memo
        memo2_text = "Memo bravo"
        memo2_block = dbf_memo_write(self.test_filename + ".DBT", 1, memo2_text)
        values2 = ['', 'BRAVO', '33', '4.4', 'F', '20240216', str(memo2_block)]
        dbf_file_append_row(dbf, values2)
        
        # Row 3: CHARLIE with memo
        memo3_text = "Memo charlie"
        memo3_block = dbf_memo_write(self.test_filename + ".DBT", 1, memo3_text)
        values3 = ['', 'CHARLIE', '555', '16.6', 'T', '20240317', str(memo3_block)]
        dbf_file_append_row(dbf, values3)
        
        # Row 4: DELTA without memo
        values4 = ['', 'DELTA', '7', '0.7', 'F', '20240418', '0']
        dbf_file_append_row(dbf, values4)
        
        # Test 1: Seek to first row
        dbf_file_seek_to_first_row(dbf)
        row = dbf_file_read_row(dbf)
        self.assertEqual(row[1].strip(), 'ALPHA')
        self.assertEqual(row[2].strip(), '1')
        self.assertEqual(row[3].strip(), '2.2')
        self.assertEqual(row[4].strip(), 'T')
        self.assertEqual(row[5].strip(), '20240115')
        self.assertEqual(row[6].strip(), str(memo1_block))
        
        # Verify first row memo
        _, memo1 = dbf_memo_read_small(self.test_filename + ".DBT", memo1_block)
        self.assertEqual(memo1, memo1_text)
        
        # Test 2: Get row count and seek to last row
        row_count = dbf_file_get_actual_row_count(dbf)
        self.assertGreater(row_count, 0)
        self.assertEqual(row_count, 4)
        
        # Seek to last row (row_count - 1)
        dbf_file_seek_to_row(dbf, row_count - 1)
        last_row = dbf_file_read_row(dbf)
        self.assertEqual(last_row[1].strip(), 'DELTA')
        self.assertEqual(last_row[2].strip(), '7')
        self.assertEqual(last_row[3].strip(), '0.7')
        self.assertEqual(last_row[4].strip(), 'F')
        self.assertEqual(last_row[5].strip(), '20240418')
        self.assertEqual(last_row[6].strip(), '0')  # No memo
        
        # Test 3: Seek to row 2 (CHARLIE - index 2)
        dbf_file_seek_to_row(dbf, 2)
        row3 = dbf_file_read_row(dbf)
        self.assertEqual(row3[1].strip(), 'CHARLIE')
        self.assertEqual(row3[2].strip(), '555')
        self.assertEqual(row3[3].strip(), '16.6')
        self.assertEqual(row3[4].strip(), 'T')
        self.assertEqual(row3[5].strip(), '20240317')
        self.assertEqual(row3[6].strip(), str(memo3_block))
        
        # Verify row 3 memo
        _, memo3 = dbf_memo_read_small(self.test_filename + ".DBT", memo3_block)
        self.assertEqual(memo3, memo3_text)
        
        # Close file
        dbf_file_close(dbf)
    
    def test_row_delete(self):
        """Test deleting and undeleting rows (matches TestRowDelete)."""
        # Create database and add 4 rows
        header = init_test_header()
        dbf = dbf_file_create(self.test_filename, header)
        
        # Add to cleanup
        self.test_files.append(self.test_filename + ".DBF")
        
        # Add the same 4 rows
        # Row 1: ALPHA with memo
        memo1_text = "Memo alpha"
        memo1_block = dbf_memo_write(self.test_filename + ".DBT", 1, memo1_text)
        values1 = ['', 'ALPHA', '1', '2.2', 'T', '20240115', str(memo1_block)]
        dbf_file_append_row(dbf, values1)
        
        # Row 2: BRAVO with memo
        memo2_text = "Memo bravo"
        memo2_block = dbf_memo_write(self.test_filename + ".DBT", 1, memo2_text)
        values2 = ['', 'BRAVO', '33', '4.4', 'F', '20240216', str(memo2_block)]
        dbf_file_append_row(dbf, values2)
        
        # Row 3: CHARLIE with memo
        memo3_text = "Memo charlie"
        memo3_block = dbf_memo_write(self.test_filename + ".DBT", 1, memo3_text)
        values3 = ['', 'CHARLIE', '555', '16.6', 'T', '20240317', str(memo3_block)]
        dbf_file_append_row(dbf, values3)
        
        # Row 4: DELTA without memo
        values4 = ['', 'DELTA', '7', '0.7', 'F', '20240418', '0']
        dbf_file_append_row(dbf, values4)
        
        # Test 1: Delete row 1 (BRAVO - index 1)
        dbf_file_set_row_deleted(dbf, 1, True)
        
        # Read row 1 and verify delete flag
        dbf_file_seek_to_row(dbf, 1)
        row = dbf_file_read_row(dbf)
        self.assertEqual(row[0], '*', "Row should be marked as deleted")
        self.assertEqual(row[1].strip(), 'BRAVO')  # Data still there
        
        # Test 2: Undelete row 1
        dbf_file_set_row_deleted(dbf, 1, False)
        
        # Read row 1 and verify delete flag is cleared
        dbf_file_seek_to_row(dbf, 1)
        row = dbf_file_read_row(dbf)
        self.assertEqual(row[0], ' ', "Row should not be marked as deleted")
        self.assertEqual(row[1].strip(), 'BRAVO')
        
        # Test 3: Verify row count
        row_count = dbf_file_get_actual_row_count(dbf)
        self.assertEqual(row_count, 4, "Row count should be 4")
        
        # Close file
        dbf_file_close(dbf)
    
    def test_row_update(self):
        """Test updating an entire row (matches TestRowUpdate)."""
        # Create database and add 4 rows
        header = init_test_header()
        dbf = dbf_file_create(self.test_filename, header)
        
        # Add to cleanup
        self.test_files.append(self.test_filename + ".DBF")
        
        # Add the same 4 rows
        # Row 1: ALPHA with memo
        memo1_text = "Memo alpha"
        memo1_block = dbf_memo_write(self.test_filename + ".DBT", 1, memo1_text)
        values1 = ['', 'ALPHA', '1', '2.2', 'T', '20240115', str(memo1_block)]
        dbf_file_append_row(dbf, values1)
        
        # Row 2: BRAVO with memo
        memo2_text = "Memo bravo"
        memo2_block = dbf_memo_write(self.test_filename + ".DBT", 1, memo2_text)
        values2 = ['', 'BRAVO', '33', '4.4', 'F', '20240216', str(memo2_block)]
        dbf_file_append_row(dbf, values2)
        
        # Row 3: CHARLIE with memo
        memo3_text = "Memo charlie"
        memo3_block = dbf_memo_write(self.test_filename + ".DBT", 1, memo3_text)
        values3 = ['', 'CHARLIE', '555', '16.6', 'T', '20240317', str(memo3_block)]
        dbf_file_append_row(dbf, values3)
        
        # Row 4: DELTA without memo
        values4 = ['', 'DELTA', '7', '0.7', 'F', '20240418', '0']
        dbf_file_append_row(dbf, values4)
        
        # Update row 2 (CHARLIE - index 2) with new values
        dbf_file_seek_to_row(dbf, 2)
        memo_lambda = dbf_memo_write(self.test_filename + ".DBT", 1, "Memo lambda")
        self.assertGreater(memo_lambda, 0)
        
        new_values = ['', 'LAMBDA', '909', '28.8', 'F', '20200103', str(memo_lambda)]
        dbf_file_write_row(dbf, new_values)
        
        # Read back and verify
        dbf_file_seek_to_row(dbf, 2)
        row = dbf_file_read_row(dbf)
        self.assertEqual(row[1].strip(), 'LAMBDA')
        self.assertEqual(row[2].strip(), '909')
        self.assertEqual(row[3].strip(), '28.8')
        self.assertEqual(row[4].strip(), 'F')
        self.assertEqual(row[5].strip(), '20200103')
        self.assertEqual(row[6].strip(), str(memo_lambda))
        
        # Verify memo
        _, memo = dbf_memo_read_small(self.test_filename + ".DBT", memo_lambda)
        self.assertEqual(memo, "Memo lambda")
        
        # Close file
        dbf_file_close(dbf)
    
    def test_row_update_by_field(self):
        """Test updating specific fields in a row (matches TestRowUpdateByField)."""
        # Create database and add 4 rows
        header = init_test_header()
        dbf = dbf_file_create(self.test_filename, header)
        
        # Add to cleanup
        self.test_files.append(self.test_filename + ".DBF")
        
        # Add the same 4 rows
        # Row 1: ALPHA with memo
        memo1_text = "Memo alpha"
        memo1_block = dbf_memo_write(self.test_filename + ".DBT", 1, memo1_text)
        values1 = ['', 'ALPHA', '1', '2.2', 'T', '20240115', str(memo1_block)]
        dbf_file_append_row(dbf, values1)
        
        # Row 2: BRAVO with memo
        memo2_text = "Memo bravo"
        memo2_block = dbf_memo_write(self.test_filename + ".DBT", 1, memo2_text)
        values2 = ['', 'BRAVO', '33', '4.4', 'F', '20240216', str(memo2_block)]
        dbf_file_append_row(dbf, values2)
        
        # Row 3: CHARLIE with memo
        memo3_text = "Memo charlie"
        memo3_block = dbf_memo_write(self.test_filename + ".DBT", 1, memo3_text)
        values3 = ['', 'CHARLIE', '555', '16.6', 'T', '20240317', str(memo3_block)]
        dbf_file_append_row(dbf, values3)
        
        # Row 4: DELTA without memo
        values4 = ['', 'DELTA', '7', '0.7', 'F', '20240418', '0']
        dbf_file_append_row(dbf, values4)
        
        # Read row 1 (BRAVO - index 1)
        dbf_file_seek_to_row(dbf, 1)
        row = dbf_file_read_row(dbf)
        
        # Update specific fields
        dbf_file_set_field_str(row, dbf, 1, 'BRAVO2')     # Field 1: TEXT
        dbf_file_set_field_str(row, dbf, 3, '7.7')        # Field 3: DECIMAL
        dbf_file_set_field_str(row, dbf, 4, 'T')          # Field 4: FLAG
        
        # Write new memo
        memo_updated = dbf_memo_write(self.test_filename + ".DBT", 1, "Memo bravo updated")
        self.assertGreater(memo_updated, 0)
        dbf_file_set_field_str(row, dbf, 6, str(memo_updated))  # Field 6: MEMO
        
        # Build values array from updated row
        values = ['']  # Index 0 is ignored
        for i in range(1, 7):
            values.append(trim_string(dbf_file_get_field_str(row, dbf, i)))
        
        # Write the updated row back
        dbf_file_seek_to_row(dbf, 1)
        dbf_file_write_row(dbf, values)
        
        # Read back and verify
        dbf_file_seek_to_row(dbf, 1)
        row = dbf_file_read_row(dbf)
        self.assertEqual(row[1].strip(), 'BRAVO2')
        self.assertEqual(row[2].strip(), '33')  # Unchanged
        self.assertEqual(row[3].strip(), '7.7')
        self.assertEqual(row[4].strip(), 'T')
        self.assertEqual(row[5].strip(), '20240216')  # Unchanged
        self.assertEqual(row[6].strip(), str(memo_updated))
        
        # Verify memo
        _, memo = dbf_memo_read_small(self.test_filename + ".DBT", memo_updated)
        self.assertEqual(memo, "Memo bravo updated")
        
        # Close file
        dbf_file_close(dbf)
    
    def test_reopen_and_read(self):
        """Test reopening a file and reading rows."""
        # Create database and add rows
        header = init_test_header()
        dbf = dbf_file_create(self.test_filename, header)
        
        # Add to cleanup
        self.test_files.append(self.test_filename + ".DBF")
        
        # Add two rows
        memo1_block = dbf_memo_write(self.test_filename + ".DBT", 1, "First memo")
        values1 = ['', 'FIRST', '10', '1.5', 'T', '20240101', str(memo1_block)]
        dbf_file_append_row(dbf, values1)
        
        memo2_block = dbf_memo_write(self.test_filename + ".DBT", 1, "Second memo")
        values2 = ['', 'SECOND', '20', '2.5', 'F', '20240202', str(memo2_block)]
        dbf_file_append_row(dbf, values2)
        
        # Close file
        dbf_file_close(dbf)
        
        # Reopen file
        dbf2 = dbf_file_open(self.test_filename + ".DBF")
        
        # Verify header was read correctly
        self.assertEqual(dbf2.header.field_count, 6)
        self.assertEqual(dbf2.header.record_count, 2)
        
        # Read first row
        dbf_file_seek_to_row(dbf2, 0)
        row1 = dbf_file_read_row(dbf2)
        self.assertEqual(row1[1].strip(), 'FIRST')
        self.assertEqual(row1[2].strip(), '10')
        
        # Read second row
        dbf_file_seek_to_row(dbf2, 1)
        row2 = dbf_file_read_row(dbf2)
        self.assertEqual(row2[1].strip(), 'SECOND')
        self.assertEqual(row2[2].strip(), '20')
        
        # Close file
        dbf_file_close(dbf2)
    
    def test_field_truncation(self):
        """Test that field values are truncated to field length."""
        # Create database
        header = init_test_header()
        dbf = dbf_file_create(self.test_filename, header)
        
        # Add to cleanup
        self.test_files.append(self.test_filename + ".DBF")
        
        # Try to write value longer than field length
        # TEXT field is 10 characters
        values = ['', 'VERYLONGTEXT', '1', '1.0', 'T', '20240101', '0']
        dbf_file_append_row(dbf, values)
        
        # Read back
        dbf_file_seek_to_row(dbf, 0)
        row = dbf_file_read_row(dbf)
        
        # Should be truncated to 10 characters
        self.assertEqual(row[1], 'VERYLONGTE')
        
        # Close file
        dbf_file_close(dbf)
    
    def test_field_padding(self):
        """Test that short field values are padded with spaces."""
        # Create database
        header = init_test_header()
        dbf = dbf_file_create(self.test_filename, header)
        
        # Add to cleanup
        self.test_files.append(self.test_filename + ".DBF")
        
        # Write short values
        values = ['', 'AB', '1', '1.0', 'T', '20240101', '0']
        dbf_file_append_row(dbf, values)
        
        # Read back
        dbf_file_seek_to_row(dbf, 0)
        row = dbf_file_read_row(dbf)
        
        # Should be padded to 10 characters
        self.assertEqual(len(row[1]), 10)
        self.assertEqual(row[1].strip(), 'AB')
        
        # Close file
        dbf_file_close(dbf)


def demo_row_operations():
    """Demonstrate row operations."""
    print("DBF Row Operations Demo")
    print("=" * 60)
    
    # Create database
    filename = "demo_rows"
    header = init_test_header()
    dbf = dbf_file_create(filename, header)
    
    print(f"\nCreated: {filename}.DBF")
    print(f"  Fields: {header.field_count}")
    print(f"  Structure:")
    for i, field in enumerate(header.fields, 1):
        print(f"    {i}. {field.name:10} {field.field_type}({field.length},{field.decimals})")
    
    # Add rows
    print("\nAdding rows...")
    
    # Row 1: ALPHA with memo
    memo1_text = "Memo alpha"
    memo1_block = dbf_memo_write(filename + ".DBT", 1, memo1_text)
    values1 = ['', 'ALPHA', '1', '2.2', 'T', '20240115', str(memo1_block)]
    dbf_file_append_row(dbf, values1)
    print(f"  Row 1: ALPHA, 1, 2.2, T, 20240115, memo block {memo1_block}")
    
    # Row 2: BRAVO with memo
    memo2_text = "Memo bravo"
    memo2_block = dbf_memo_write(filename + ".DBT", 1, memo2_text)
    values2 = ['', 'BRAVO', '33', '4.4', 'F', '20240216', str(memo2_block)]
    dbf_file_append_row(dbf, values2)
    print(f"  Row 2: BRAVO, 33, 4.4, F, 20240216, memo block {memo2_block}")
    
    # Row 3: CHARLIE with memo
    memo3_text = "Memo charlie"
    memo3_block = dbf_memo_write(filename + ".DBT", 1, memo3_text)
    values3 = ['', 'CHARLIE', '555', '16.6', 'T', '20240317', str(memo3_block)]
    dbf_file_append_row(dbf, values3)
    print(f"  Row 3: CHARLIE, 555, 16.6, T, 20240317, memo block {memo3_block}")
    
    # Row 4: DELTA without memo
    values4 = ['', 'DELTA', '7', '0.7', 'F', '20240418', '0']
    dbf_file_append_row(dbf, values4)
    print(f"  Row 4: DELTA, 7, 0.7, F, 20240418, no memo")
    
    # Read rows back
    print("\nReading rows...")
    
    dbf_file_seek_to_row(dbf, 0)
    row1 = dbf_file_read_row(dbf)
    print(f"  Row 1: {row1[1].strip()}, {row1[2].strip()}, {row1[3].strip()}, {row1[4].strip()}, {row1[5].strip()}, memo={row1[6].strip()}")
    
    dbf_file_seek_to_row(dbf, 1)
    row2 = dbf_file_read_row(dbf)
    print(f"  Row 2: {row2[1].strip()}, {row2[2].strip()}, {row2[3].strip()}, {row2[4].strip()}, {row2[5].strip()}, memo={row2[6].strip()}")
    
    dbf_file_seek_to_row(dbf, 2)
    row3 = dbf_file_read_row(dbf)
    print(f"  Row 3: {row3[1].strip()}, {row3[2].strip()}, {row3[3].strip()}, {row3[4].strip()}, {row3[5].strip()}, memo={row3[6].strip()}")
    
    dbf_file_seek_to_row(dbf, 3)
    row4 = dbf_file_read_row(dbf)
    print(f"  Row 4: {row4[1].strip()}, {row4[2].strip()}, {row4[3].strip()}, {row4[4].strip()}, {row4[5].strip()}, memo={row4[6].strip()}")
    
    # Close file
    dbf_file_close(dbf)
    
    # Cleanup
    if os.path.exists(filename + ".DBF"):
        os.remove(filename + ".DBF")
    if os.path.exists(filename + ".DBT"):
        os.remove(filename + ".DBT")
    
    print("\nDemo completed successfully!")


if __name__ == "__main__":
    # Run the demo
    demo_row_operations()
    
    # Run the tests
    print("\n" + "=" * 60)
    print("Running unit tests...")
    print("=" * 60)
    unittest.main()
