"""
Test file for DBF version byte validation.
This verifies that the version byte is set correctly based on memo field presence.
"""

import os
import datetime
import unittest
from dbf_module import (
    DBFColumn, DBFHeader, DBFFile,
    dbf_file_create, dbf_file_create_dbase3, dbf_file_close, dbf_file_open
)


class TestDBFVersion(unittest.TestCase):
    """Test cases for DBF version byte validation."""
    
    def setUp(self):
        """Set up test environment."""
        self.test_files = []
        
    def tearDown(self):
        """Clean up test files."""
        for filename in self.test_files:
            if os.path.exists(filename):
                try:
                    os.remove(filename)
                except:
                    pass
            
            # Also try to remove memo file if it exists
            memo_file = filename.replace('.DBF', '.DBT')
            if os.path.exists(memo_file):
                try:
                    os.remove(memo_file)
                except:
                    pass
    
    def test_dbase4_without_memo(self):
        """Test that dBase IV without memo fields has version 0x04."""
        # Define fields without memo
        fields = [
            DBFColumn(name="ID", field_type="N", length=5, decimals=0),
            DBFColumn(name="NAME", field_type="C", length=30, decimals=0),
            DBFColumn(name="ACTIVE", field_type="L", length=1, decimals=0)
        ]
        
        # Create header
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        header.version = 0x04  # Force dBase IV
        
        # Create the file
        filename = "test_v4_no_memo"
        dbf = dbf_file_create(filename, header)
        
        # Verify version in memory
        self.assertEqual(dbf.header.version, 0x04, "Version should be 0x04 for dBase IV without memo")
        
        # Close the file
        dbf_file_close(dbf)
        
        # Add to cleanup list
        self.test_files.append(filename + ".DBF")
        
        # Read binary file and check version byte
        with open(filename + ".DBF", "rb") as f:
            version_byte = f.read(1)[0]
        
        self.assertEqual(version_byte, 0x04, "Version byte should be 0x04 in file")
        
        # Verify no memo file was created
        self.assertFalse(os.path.exists(filename + ".DBT"), "No memo file should be created")
        
        # Reopen and verify
        dbf = dbf_file_open(filename)
        self.assertEqual(dbf.header.version, 0x04, "Version should be 0x04 after reopen")
        dbf_file_close(dbf)
    
    def test_dbase4_with_memo(self):
        """Test that dBase IV with memo fields has version 0x05."""
        # Define fields with memo
        fields = [
            DBFColumn(name="ID", field_type="N", length=5, decimals=0),
            DBFColumn(name="NAME", field_type="C", length=30, decimals=0),
            DBFColumn(name="NOTES", field_type="M", length=10, decimals=0)  # Memo field
        ]
        
        # Create header - start with version 0x04
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        header.version = 0x04  # Start with dBase IV
        
        # Create the file - should automatically upgrade to 0x05
        filename = "test_v4_with_memo"
        dbf = dbf_file_create(filename, header)
        
        # Verify version was upgraded to 0x05
        self.assertEqual(dbf.header.version, 0x05, "Version should be 0x05 for dBase IV with memo")
        
        # Close the file
        dbf_file_close(dbf)
        
        # Add to cleanup list
        self.test_files.append(filename + ".DBF")
        
        # Read binary file and check version byte
        with open(filename + ".DBF", "rb") as f:
            version_byte = f.read(1)[0]
        
        self.assertEqual(version_byte, 0x05, "Version byte should be 0x05 in file")
        
        # Verify memo file was created
        self.assertTrue(os.path.exists(filename + ".DBT"), "Memo file should be created")
        
        # Reopen and verify
        dbf = dbf_file_open(filename)
        self.assertEqual(dbf.header.version, 0x05, "Version should be 0x05 after reopen")
        dbf_file_close(dbf)
    
    def test_dbase5_without_memo_downgrade(self):
        """Test that dBase V without memo fields downgrades to 0x04."""
        # Define fields without memo
        fields = [
            DBFColumn(name="ID", field_type="N", length=5, decimals=0),
            DBFColumn(name="NAME", field_type="C", length=30, decimals=0)
        ]
        
        # Create header with version 0x05
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        header.version = 0x05  # Start with dBase V
        
        # Create the file - should automatically downgrade to 0x04
        filename = "test_v5_no_memo"
        dbf = dbf_file_create(filename, header)
        
        # Verify version was downgraded to 0x04
        self.assertEqual(dbf.header.version, 0x04, "Version should be 0x04 when no memo fields")
        
        # Close the file
        dbf_file_close(dbf)
        
        # Add to cleanup list
        self.test_files.append(filename + ".DBF")
        
        # Read binary file and check version byte
        with open(filename + ".DBF", "rb") as f:
            version_byte = f.read(1)[0]
        
        self.assertEqual(version_byte, 0x04, "Version byte should be 0x04 in file")
        
        # Verify no memo file was created
        self.assertFalse(os.path.exists(filename + ".DBT"), "No memo file should be created")
    
    def test_auto_version_with_memo(self):
        """Test that version is auto-set to 0x05 when memo fields present and version is 0."""
        # Define fields with memo
        fields = [
            DBFColumn(name="ID", field_type="N", length=5, decimals=0),
            DBFColumn(name="NOTES", field_type="M", length=10, decimals=0)
        ]
        
        # Create header with version 0 (auto-detect)
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        header.version = 0  # Auto-detect
        
        # Create the file
        filename = "test_auto_memo"
        dbf = dbf_file_create(filename, header)
        
        # Verify version was set to 0x05
        self.assertEqual(dbf.header.version, 0x05, "Version should be auto-set to 0x05 with memo")
        
        # Close the file
        dbf_file_close(dbf)
        
        # Add to cleanup list
        self.test_files.append(filename + ".DBF")
        
        # Verify memo file was created
        self.assertTrue(os.path.exists(filename + ".DBT"), "Memo file should be created")
    
    def test_auto_version_without_memo(self):
        """Test that version is auto-set to 0x04 when no memo fields and version is 0."""
        # Define fields without memo
        fields = [
            DBFColumn(name="ID", field_type="N", length=5, decimals=0),
            DBFColumn(name="NAME", field_type="C", length=30, decimals=0)
        ]
        
        # Create header with version 0 (auto-detect)
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        header.version = 0  # Auto-detect
        
        # Create the file
        filename = "test_auto_no_memo"
        dbf = dbf_file_create(filename, header)
        
        # Verify version was set to 0x04
        self.assertEqual(dbf.header.version, 0x04, "Version should be auto-set to 0x04 without memo")
        
        # Close the file
        dbf_file_close(dbf)
        
        # Add to cleanup list
        self.test_files.append(filename + ".DBF")
        
        # Verify no memo file was created
        self.assertFalse(os.path.exists(filename + ".DBT"), "No memo file should be created")
    
    def test_dbase3_always_03(self):
        """Test that dBase III files always have version 0x03."""
        # Define fields
        fields = [
            DBFColumn(name="ID", field_type="N", length=5, decimals=0),
            DBFColumn(name="NAME", field_type="C", length=30, decimals=0)
        ]
        
        # Create header
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        
        # Create dBase III file
        filename = "test_v3"
        dbf = dbf_file_create_dbase3(filename, header)
        
        # Verify version is 0x03
        self.assertEqual(dbf.header.version, 0x03, "Version should be 0x03 for dBase III")
        
        # Close the file
        dbf_file_close(dbf)
        
        # Add to cleanup list
        self.test_files.append(filename + ".DBF")
        
        # Read binary file and check version byte
        with open(filename + ".DBF", "rb") as f:
            version_byte = f.read(1)[0]
        
        self.assertEqual(version_byte, 0x03, "Version byte should be 0x03 in file")
    
    def test_multiple_memo_fields(self):
        """Test that multiple memo fields still result in version 0x05."""
        # Define fields with multiple memo fields
        fields = [
            DBFColumn(name="ID", field_type="N", length=5, decimals=0),
            DBFColumn(name="NOTES", field_type="M", length=10, decimals=0),
            DBFColumn(name="COMMENTS", field_type="M", length=10, decimals=0),
            DBFColumn(name="DESC", field_type="M", length=10, decimals=0)
        ]
        
        # Create header
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        header.version = 0  # Auto-detect
        
        # Create the file
        filename = "test_multi_memo"
        dbf = dbf_file_create(filename, header)
        
        # Verify version is 0x05
        self.assertEqual(dbf.header.version, 0x05, "Version should be 0x05 with multiple memo fields")
        
        # Close the file
        dbf_file_close(dbf)
        
        # Add to cleanup list
        self.test_files.append(filename + ".DBF")
        
        # Verify memo file was created
        self.assertTrue(os.path.exists(filename + ".DBT"), "Memo file should be created")


def demo_version_detection():
    """Demonstrate version detection based on memo fields."""
    print("DBF Version Detection Demo")
    print("=" * 50)
    
    # Test 1: dBase IV without memo
    print("\nTest 1: dBase IV without memo fields")
    fields = [
        DBFColumn(name="ID", field_type="N", length=5, decimals=0),
        DBFColumn(name="NAME", field_type="C", length=30, decimals=0)
    ]
    
    header = DBFHeader()
    header.fields = fields
    header.field_count = len(fields)
    header.version = 0x04
    
    filename = "demo_v4_no_memo"
    dbf = dbf_file_create(filename, header)
    print(f"  Created with version: 0x{dbf.header.version:02X}")
    print(f"  Memo file created: {os.path.exists(filename + '.DBT')}")
    dbf_file_close(dbf)
    
    # Test 2: dBase IV with memo
    print("\nTest 2: dBase IV with memo field")
    fields = [
        DBFColumn(name="ID", field_type="N", length=5, decimals=0),
        DBFColumn(name="NOTES", field_type="M", length=10, decimals=0)
    ]
    
    header = DBFHeader()
    header.fields = fields
    header.field_count = len(fields)
    header.version = 0x04  # Start with 0x04
    
    filename = "demo_v4_with_memo"
    dbf = dbf_file_create(filename, header)
    print(f"  Requested version: 0x04")
    print(f"  Actual version: 0x{dbf.header.version:02X} (auto-upgraded)")
    print(f"  Memo file created: {os.path.exists(filename + '.DBT')}")
    dbf_file_close(dbf)
    
    # Test 3: Auto-detect
    print("\nTest 3: Auto-detect version (version = 0)")
    header = DBFHeader()
    header.fields = fields
    header.field_count = len(fields)
    header.version = 0  # Auto-detect
    
    filename = "demo_auto"
    dbf = dbf_file_create(filename, header)
    print(f"  Auto-detected version: 0x{dbf.header.version:02X}")
    print(f"  Memo file created: {os.path.exists(filename + '.DBT')}")
    dbf_file_close(dbf)
    
    # Cleanup
    for fname in ["demo_v4_no_memo", "demo_v4_with_memo", "demo_auto"]:
        if os.path.exists(fname + ".DBF"):
            os.remove(fname + ".DBF")
        if os.path.exists(fname + ".DBT"):
            os.remove(fname + ".DBT")
    
    print("\nDemo completed successfully!")


if __name__ == "__main__":
    # Run the demo
    demo_version_detection()
    
    # Run the tests
    print("\n" + "=" * 50)
    print("Running unit tests...")
    print("=" * 50)
    unittest.main()
