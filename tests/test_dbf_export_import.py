"""
Test file for DBF export and import functionality.
This tests exporting an empty table and re-importing it to verify identity.
"""

import os
import unittest
from dbf_module import (
    DBFColumn, DBFHeader, DBFFile,
    dbf_file_create, dbf_file_create_dbase3, dbf_file_close, dbf_file_open,
    dbf_file_append_row, dbf_file_read_row, dbf_file_seek_to_row,
    dbf_file_get_actual_row_count,
    export_dbf_to_text, import_dbf_from_text,
    build_field_spec, parse_field_spec,
    dbf_memo_write, dbf_memo_read_small
)


class TestDBFExportImport(unittest.TestCase):
    """Test cases for DBF export and import."""
    
    def setUp(self):
        """Set up test environment."""
        self.test_files = []
        
    def tearDown(self):
        """Clean up test files."""
        for filename in self.test_files:
            # Remove DBF file
            if os.path.exists(filename):
                try:
                    os.remove(filename)
                except:
                    pass
            
            # Remove TXT file
            txt_file = filename.replace('.DBF', '.TXT')
            if os.path.exists(txt_file):
                try:
                    os.remove(txt_file)
                except:
                    pass
            
            # Remove DBT file
            dbt_file = filename.replace('.DBF', '.DBT')
            if os.path.exists(dbt_file):
                try:
                    os.remove(dbt_file)
                except:
                    pass
    
    def compare_headers(self, header1: DBFHeader, header2: DBFHeader) -> bool:
        """Compare two DBF headers for equality."""
        if header1.field_count != header2.field_count:
            return False
        
        for i in range(header1.field_count):
            field1 = header1.fields[i]
            field2 = header2.fields[i]
            
            if field1.name != field2.name:
                return False
            if field1.field_type != field2.field_type:
                return False
            if field1.length != field2.length:
                return False
            if field1.decimals != field2.decimals:
                return False
        
        return True
    
    def test_build_field_spec(self):
        """Test building field specifications."""
        # Test character field
        field = DBFColumn(name="NAME", field_type="C", length=30, decimals=0)
        spec = build_field_spec(field)
        self.assertEqual(spec, "C(30)")
        
        # Test numeric field without decimals
        field = DBFColumn(name="ID", field_type="N", length=5, decimals=0)
        spec = build_field_spec(field)
        self.assertEqual(spec, "N(5)")
        
        # Test numeric field with decimals
        field = DBFColumn(name="SALARY", field_type="N", length=10, decimals=2)
        spec = build_field_spec(field)
        self.assertEqual(spec, "N(10,2)")
        
        # Test logical field
        field = DBFColumn(name="ACTIVE", field_type="L", length=1, decimals=0)
        spec = build_field_spec(field)
        self.assertEqual(spec, "L(1)")
    
    def test_parse_field_spec(self):
        """Test parsing field specifications."""
        # Test character field
        field_type, length, decimals = parse_field_spec("C(30)")
        self.assertEqual(field_type, "C")
        self.assertEqual(length, 30)
        self.assertEqual(decimals, 0)
        
        # Test numeric field without decimals
        field_type, length, decimals = parse_field_spec("N(5)")
        self.assertEqual(field_type, "N")
        self.assertEqual(length, 5)
        self.assertEqual(decimals, 0)
        
        # Test numeric field with decimals
        field_type, length, decimals = parse_field_spec("N(10,2)")
        self.assertEqual(field_type, "N")
        self.assertEqual(length, 10)
        self.assertEqual(decimals, 2)
        
        # Test with spaces
        field_type, length, decimals = parse_field_spec(" N ( 10 , 2 ) ")
        self.assertEqual(field_type, "N")
        self.assertEqual(length, 10)
        self.assertEqual(decimals, 2)
    
    def test_export_empty_table(self):
        """Test exporting an empty table to text."""
        # Create a simple DBF file
        fields = [
            DBFColumn(name="ID", field_type="N", length=5, decimals=0),
            DBFColumn(name="NAME", field_type="C", length=30, decimals=0),
            DBFColumn(name="ACTIVE", field_type="L", length=1, decimals=0)
        ]
        
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        
        filename = "test_export"
        dbf = dbf_file_create_dbase3(filename, header)
        dbf_file_close(dbf)
        
        # Add to cleanup list
        self.test_files.append(filename + ".DBF")
        
        # Export to text
        export_dbf_to_text(filename)
        
        # Verify text file was created
        txt_filename = filename + ".TXT"
        self.assertTrue(os.path.exists(txt_filename))
        
        # Read and verify text file content
        with open(txt_filename, 'r') as f:
            lines = f.readlines()
        
        # Should have 2 lines (field names and specs)
        self.assertEqual(len(lines), 2)
        
        # Verify field names line
        expected_names = "ID|NAME|ACTIVE\n"
        self.assertEqual(lines[0], expected_names)
        
        # Verify field specs line
        expected_specs = "N(5)|C(30)|L(1)\n"
        self.assertEqual(lines[1], expected_specs)
    
    def test_import_from_text(self):
        """Test importing a DBF file from text."""
        # Create a text file manually
        filename = "test_import"
        txt_filename = filename + ".TXT"
        
        with open(txt_filename, 'w') as f:
            f.write("ID|NAME|ACTIVE\n")
            f.write("N(5)|C(30)|L(1)\n")
        
        # Add to cleanup list
        self.test_files.append(filename + ".DBF")
        
        # Import from text
        import_dbf_from_text(filename)
        
        # Verify DBF file was created
        dbf_filename = filename + ".DBF"
        self.assertTrue(os.path.exists(dbf_filename))
        
        # Open and verify the DBF file
        dbf = dbf_file_open(dbf_filename)
        
        # Verify field count
        self.assertEqual(dbf.header.field_count, 3)
        
        # Verify field 1
        self.assertEqual(dbf.header.fields[0].name, "ID")
        self.assertEqual(dbf.header.fields[0].field_type, "N")
        self.assertEqual(dbf.header.fields[0].length, 5)
        self.assertEqual(dbf.header.fields[0].decimals, 0)
        
        # Verify field 2
        self.assertEqual(dbf.header.fields[1].name, "NAME")
        self.assertEqual(dbf.header.fields[1].field_type, "C")
        self.assertEqual(dbf.header.fields[1].length, 30)
        self.assertEqual(dbf.header.fields[1].decimals, 0)
        
        # Verify field 3
        self.assertEqual(dbf.header.fields[2].name, "ACTIVE")
        self.assertEqual(dbf.header.fields[2].field_type, "L")
        self.assertEqual(dbf.header.fields[2].length, 1)
        self.assertEqual(dbf.header.fields[2].decimals, 0)
        
        dbf_file_close(dbf)
    
    def test_export_import_roundtrip(self):
        """Test that export and import produce an identical table."""
        # Create original DBF file
        fields = [
            DBFColumn(name="ID", field_type="N", length=5, decimals=0),
            DBFColumn(name="NAME", field_type="C", length=30, decimals=0),
            DBFColumn(name="SALARY", field_type="N", length=10, decimals=2),
            DBFColumn(name="ACTIVE", field_type="L", length=1, decimals=0)
        ]
        
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        
        original_filename = "test_original"
        dbf = dbf_file_create_dbase3(original_filename, header)
        dbf_file_close(dbf)
        
        # Add to cleanup list
        self.test_files.append(original_filename + ".DBF")
        
        # Export to text
        export_dbf_to_text(original_filename)
        
        # Import to new DBF file
        imported_filename = "test_imported"
        self.test_files.append(imported_filename + ".DBF")
        
        # Rename the text file for import
        os.rename(original_filename + ".TXT", imported_filename + ".TXT")
        import_dbf_from_text(imported_filename)
        
        # Open both files and compare
        original_dbf = dbf_file_open(original_filename)
        imported_dbf = dbf_file_open(imported_filename)
        
        # Compare headers
        self.assertTrue(self.compare_headers(original_dbf.header, imported_dbf.header))
        
        # Compare field count
        self.assertEqual(original_dbf.header.field_count, imported_dbf.header.field_count)
        
        # Compare each field
        for i in range(original_dbf.header.field_count):
            orig_field = original_dbf.header.fields[i]
            imp_field = imported_dbf.header.fields[i]
            
            self.assertEqual(orig_field.name, imp_field.name, f"Field {i} name mismatch")
            self.assertEqual(orig_field.field_type, imp_field.field_type, f"Field {i} type mismatch")
            self.assertEqual(orig_field.length, imp_field.length, f"Field {i} length mismatch")
            self.assertEqual(orig_field.decimals, imp_field.decimals, f"Field {i} decimals mismatch")
        
        dbf_file_close(original_dbf)
        dbf_file_close(imported_dbf)
    
    def test_export_import_with_memo_field(self):
        """Test export/import with memo fields."""
        # Create DBF file with memo field
        fields = [
            DBFColumn(name="ID", field_type="N", length=5, decimals=0),
            DBFColumn(name="NOTES", field_type="M", length=10, decimals=0)
        ]
        
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        
        filename = "test_memo"
        dbf = dbf_file_create(filename, header)
        dbf_file_close(dbf)
        
        # Add to cleanup list
        self.test_files.append(filename + ".DBF")
        
        # Export to text
        export_dbf_to_text(filename)
        
        # Verify text file content
        with open(filename + ".TXT", 'r') as f:
            lines = f.readlines()
        
        self.assertEqual(lines[0], "ID|NOTES\n")
        self.assertEqual(lines[1], "N(5)|M(10)\n")
        
        # Import to new file
        imported_filename = "test_memo_imported"
        self.test_files.append(imported_filename + ".DBF")
        
        os.rename(filename + ".TXT", imported_filename + ".TXT")
        import_dbf_from_text(imported_filename)
        
        # Verify imported file
        dbf = dbf_file_open(imported_filename)
        self.assertEqual(dbf.header.field_count, 2)
        self.assertEqual(dbf.header.fields[1].field_type, "M")
        self.assertEqual(dbf.header.version, 0x05)  # Should be version 5 with memo
        dbf_file_close(dbf)
    
    def test_export_import_with_data(self):
        """Test export/import with actual row data."""
        # Create DBF file with data
        fields = [
            DBFColumn(name="ID", field_type="N", length=5, decimals=0),
            DBFColumn(name="NAME", field_type="C", length=20, decimals=0),
            DBFColumn(name="SALARY", field_type="N", length=10, decimals=2),
            DBFColumn(name="ACTIVE", field_type="L", length=1, decimals=0),
            DBFColumn(name="HIRED", field_type="D", length=8, decimals=0)
        ]
        
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        
        original_filename = "test_data_original"
        dbf = dbf_file_create_dbase3(original_filename, header)
        
        # Add to cleanup list
        self.test_files.append(original_filename + ".DBF")
        
        # Add test data
        row1 = ['', '1', 'Alice', '50000.50', 'T', '20200115']
        row2 = ['', '2', 'Bob', '60000.75', 'F', '20210220']
        row3 = ['', '3', 'Charlie', '55000.00', 'T', '20190310']
        
        dbf_file_append_row(dbf, row1)
        dbf_file_append_row(dbf, row2)
        dbf_file_append_row(dbf, row3)
        
        dbf_file_close(dbf)
        
        # Export to text
        export_dbf_to_text(original_filename)
        
        # Import to new DBF file
        imported_filename = "test_data_imported"
        self.test_files.append(imported_filename + ".DBF")
        
        # Rename the text file for import
        os.rename(original_filename + ".TXT", imported_filename + ".TXT")
        import_dbf_from_text(imported_filename)
        
        # Open imported file and verify data
        imported_dbf = dbf_file_open(imported_filename)
        
        # Verify row count
        row_count = dbf_file_get_actual_row_count(imported_dbf)
        self.assertEqual(row_count, 3, "Should have 3 rows")
        
        # Verify row 1
        dbf_file_seek_to_row(imported_dbf, 0)
        row = dbf_file_read_row(imported_dbf)
        self.assertEqual(row[1].strip(), '1')
        self.assertEqual(row[2].strip(), 'Alice')
        self.assertEqual(row[3].strip(), '50000.50')
        self.assertEqual(row[4].strip(), 'T')
        self.assertEqual(row[5].strip(), '20200115')
        
        # Verify row 2
        dbf_file_seek_to_row(imported_dbf, 1)
        row = dbf_file_read_row(imported_dbf)
        self.assertEqual(row[1].strip(), '2')
        self.assertEqual(row[2].strip(), 'Bob')
        self.assertEqual(row[3].strip(), '60000.75')
        self.assertEqual(row[4].strip(), 'F')
        self.assertEqual(row[5].strip(), '20210220')
        
        # Verify row 3
        dbf_file_seek_to_row(imported_dbf, 2)
        row = dbf_file_read_row(imported_dbf)
        self.assertEqual(row[1].strip(), '3')
        self.assertEqual(row[2].strip(), 'Charlie')
        self.assertEqual(row[3].strip(), '55000.00')
        self.assertEqual(row[4].strip(), 'T')
        self.assertEqual(row[5].strip(), '20190310')
        
        dbf_file_close(imported_dbf)
    
    def test_export_import_with_memo_data(self):
        """Test export/import with memo field data (memo block numbers only)."""
        # Note: Export/import preserves memo block numbers but not memo content
        # The memo file (.DBT) is not exported/imported, only the structure and row data
        
        # Create DBF file with memo field
        fields = [
            DBFColumn(name="ID", field_type="N", length=5, decimals=0),
            DBFColumn(name="NAME", field_type="C", length=20, decimals=0),
            DBFColumn(name="NOTES", field_type="M", length=10, decimals=0)
        ]
        
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        
        original_filename = "test_memo_data_original"
        dbf = dbf_file_create(original_filename, header)
        
        # Add to cleanup list
        self.test_files.append(original_filename + ".DBF")
        
        # Add test data with memos
        memo1 = dbf_memo_write(original_filename + ".DBT", 1, "First memo text")
        memo2 = dbf_memo_write(original_filename + ".DBT", 1, "Second memo text with more content")
        
        row1 = ['', '1', 'Alice', str(memo1)]
        row2 = ['', '2', 'Bob', str(memo2)]
        row3 = ['', '3', 'Charlie', '0']  # No memo
        
        dbf_file_append_row(dbf, row1)
        dbf_file_append_row(dbf, row2)
        dbf_file_append_row(dbf, row3)
        
        dbf_file_close(dbf)
        
        # Export to text
        export_dbf_to_text(original_filename)
        
        # Import to new DBF file
        imported_filename = "test_memo_data_imported"
        self.test_files.append(imported_filename + ".DBF")
        
        # Rename the text file for import
        os.rename(original_filename + ".TXT", imported_filename + ".TXT")
        import_dbf_from_text(imported_filename)
        
        # Open imported file and verify data
        imported_dbf = dbf_file_open(imported_filename)
        
        # Verify row count
        row_count = dbf_file_get_actual_row_count(imported_dbf)
        self.assertEqual(row_count, 3, "Should have 3 rows")
        
        # Verify row 1 - memo block numbers are preserved
        dbf_file_seek_to_row(imported_dbf, 0)
        row = dbf_file_read_row(imported_dbf)
        self.assertEqual(row[1].strip(), '1')
        self.assertEqual(row[2].strip(), 'Alice')
        self.assertEqual(row[3].strip(), str(memo1))  # Block number preserved
        
        # Verify row 2
        dbf_file_seek_to_row(imported_dbf, 1)
        row = dbf_file_read_row(imported_dbf)
        self.assertEqual(row[1].strip(), '2')
        self.assertEqual(row[2].strip(), 'Bob')
        self.assertEqual(row[3].strip(), str(memo2))  # Block number preserved
        
        # Verify row 3 (no memo)
        dbf_file_seek_to_row(imported_dbf, 2)
        row = dbf_file_read_row(imported_dbf)
        self.assertEqual(row[1].strip(), '3')
        self.assertEqual(row[2].strip(), 'Charlie')
        self.assertEqual(row[3].strip(), '0')
        
        dbf_file_close(imported_dbf)


def demo_export_import():
    """Demonstrate export and import functionality."""
    print("DBF Export/Import Demo")
    print("=" * 60)
    
    # Create a sample DBF file
    fields = [
        DBFColumn(name="ID", field_type="N", length=5, decimals=0),
        DBFColumn(name="NAME", field_type="C", length=30, decimals=0),
        DBFColumn(name="SALARY", field_type="N", length=10, decimals=2),
        DBFColumn(name="ACTIVE", field_type="L", length=1, decimals=0)
    ]
    
    header = DBFHeader()
    header.fields = fields
    header.field_count = len(fields)
    
    filename = "demo_export"
    dbf = dbf_file_create_dbase3(filename, header)
    dbf_file_close(dbf)
    
    print(f"\nCreated DBF file: {filename}.DBF")
    print(f"  Fields: {header.field_count}")
    
    # Export to text
    export_dbf_to_text(filename)
    print(f"\nExported to: {filename}.TXT")
    
    # Display text file content
    with open(filename + ".TXT", 'r') as f:
        content = f.read()
    print("\nText file content:")
    print(content)
    
    # Import to new file
    imported_filename = "demo_imported"
    os.rename(filename + ".TXT", imported_filename + ".TXT")
    import_dbf_from_text(imported_filename)
    
    print(f"Imported to: {imported_filename}.DBF")
    
    # Compare files
    original_dbf = dbf_file_open(filename)
    imported_dbf = dbf_file_open(imported_filename)
    
    print("\nComparison:")
    print(f"  Original fields: {original_dbf.header.field_count}")
    print(f"  Imported fields: {imported_dbf.header.field_count}")
    print(f"  Headers match: {original_dbf.header.field_count == imported_dbf.header.field_count}")
    
    dbf_file_close(original_dbf)
    dbf_file_close(imported_dbf)
    
    # Cleanup
    for fname in [filename, imported_filename]:
        if os.path.exists(fname + ".DBF"):
            os.remove(fname + ".DBF")
        if os.path.exists(fname + ".TXT"):
            os.remove(fname + ".TXT")
        if os.path.exists(fname + ".DBT"):
            os.remove(fname + ".DBT")
    
    print("\nDemo completed successfully!")


if __name__ == "__main__":
    # Run the demo
    demo_export_import()
    
    # Run the tests
    print("\n" + "=" * 60)
    print("Running unit tests...")
    print("=" * 60)
    unittest.main()
