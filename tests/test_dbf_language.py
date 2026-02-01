"""
Test file for DBF language driver functions.
This demonstrates how to get and set the language driver in DBF files.
"""

import os
import datetime
import unittest
from dbf_module import (
    DBFColumn, DBFHeader, DBFFile,
    dbf_file_create, dbf_file_create_dbase3, dbf_file_close, dbf_file_open,
    dbf_file_get_language_driver, dbf_file_set_language_driver,
    DBF_LANG_US, DBF_LANG_WESTERN_EUROPE, DBF_LANG_JAPAN
)


class TestDBFLanguageDriver(unittest.TestCase):
    """Test cases for DBF language driver functions."""
    
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
    
    def test_dbase3_language_driver_is_zero(self):
        """Test that dBase III files have language driver set to 0."""
        # Define test fields
        fields = [
            DBFColumn(name="ID", field_type="N", length=5, decimals=0),
            DBFColumn(name="NAME", field_type="C", length=30, decimals=0)
        ]
        
        # Create header
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        
        # Create dBase III file
        filename = "test_lang_dbase3"
        dbf = dbf_file_create_dbase3(filename, header)
        
        # Get the language driver
        lang = dbf_file_get_language_driver(dbf)
        
        # Verify it's 0 for dBase III
        self.assertEqual(lang, 0, "dBase III should have language driver = 0")
        
        # Close the file
        dbf_file_close(dbf)
        
        # Add to cleanup list
        self.test_files.append(filename + ".DBF")
        
        # Reopen and verify
        dbf = dbf_file_open(filename)
        lang = dbf_file_get_language_driver(dbf)
        self.assertEqual(lang, 0, "dBase III should have language driver = 0 after reopen")
        dbf_file_close(dbf)
    
    def test_dbase4_default_language_driver(self):
        """Test that dBase IV files have default language driver set to US."""
        # Define test fields
        fields = [
            DBFColumn(name="ID", field_type="N", length=5, decimals=0),
            DBFColumn(name="NAME", field_type="C", length=30, decimals=0)
        ]
        
        # Create header
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        header.version = 0x04  # Force dBase IV
        
        # Create dBase IV file
        filename = "test_lang_dbase4"
        dbf = dbf_file_create(filename, header)
        
        # Get the language driver
        lang = dbf_file_get_language_driver(dbf)
        
        # Verify it's US (1) for dBase IV
        self.assertEqual(lang, DBF_LANG_US, "dBase IV should have language driver = US (1)")
        
        # Close the file
        dbf_file_close(dbf)
        
        # Add to cleanup list
        self.test_files.append(filename + ".DBF")
    
    def test_set_language_driver_dbase4(self):
        """Test setting the language driver in a dBase IV file."""
        # Define test fields
        fields = [
            DBFColumn(name="ID", field_type="N", length=5, decimals=0),
            DBFColumn(name="NAME", field_type="C", length=30, decimals=0)
        ]
        
        # Create header
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        header.version = 0x04  # Force dBase IV
        
        # Create dBase IV file
        filename = "test_lang_set"
        dbf = dbf_file_create(filename, header)
        
        # Set language driver to Western Europe
        dbf_file_set_language_driver(dbf, DBF_LANG_WESTERN_EUROPE)
        
        # Get the language driver to verify
        lang = dbf_file_get_language_driver(dbf)
        self.assertEqual(lang, DBF_LANG_WESTERN_EUROPE)
        
        # Close the file
        dbf_file_close(dbf)
        
        # Add to cleanup list
        self.test_files.append(filename + ".DBF")
        
        # Reopen the file and verify the language driver was persisted
        dbf = dbf_file_open(filename)
        lang = dbf_file_get_language_driver(dbf)
        self.assertEqual(lang, DBF_LANG_WESTERN_EUROPE)
        
        dbf_file_close(dbf)
    
    def test_set_language_driver_japan(self):
        """Test setting the language driver to Japan."""
        # Define test fields
        fields = [
            DBFColumn(name="ID", field_type="N", length=5, decimals=0),
            DBFColumn(name="NAME", field_type="C", length=30, decimals=0)
        ]
        
        # Create header
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        header.version = 0x04  # Force dBase IV
        
        # Create dBase IV file
        filename = "test_lang_japan"
        dbf = dbf_file_create(filename, header)
        
        # Set language driver to Japan
        dbf_file_set_language_driver(dbf, DBF_LANG_JAPAN)
        
        # Get the language driver to verify
        lang = dbf_file_get_language_driver(dbf)
        self.assertEqual(lang, DBF_LANG_JAPAN)
        
        # Close the file
        dbf_file_close(dbf)
        
        # Add to cleanup list
        self.test_files.append(filename + ".DBF")
        
        # Reopen the file and verify the language driver was persisted
        dbf = dbf_file_open(filename)
        lang = dbf_file_get_language_driver(dbf)
        self.assertEqual(lang, DBF_LANG_JAPAN)
        
        dbf_file_close(dbf)
    
    def test_language_driver_binary_position(self):
        """Test that the language driver is written to the correct byte position."""
        # Define test fields
        fields = [
            DBFColumn(name="ID", field_type="N", length=5, decimals=0)
        ]
        
        # Create header
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        header.version = 0x04
        
        # Create dBase IV file
        filename = "test_lang_binary"
        dbf = dbf_file_create(filename, header)
        
        # Set language driver to a specific value
        test_value = 0x42  # Arbitrary test value
        dbf_file_set_language_driver(dbf, test_value)
        
        # Close the file
        dbf_file_close(dbf)
        
        # Add to cleanup list
        self.test_files.append(filename + ".DBF")
        
        # Read the binary file and check byte 29
        with open(filename + ".DBF", "rb") as f:
            f.seek(29)
            byte_29 = f.read(1)[0]
        
        self.assertEqual(byte_29, test_value, "Language driver should be at byte 29")


def demo_language_driver_functions():
    """Demonstrate the language driver functions."""
    print("DBF Language Driver Functions Demo")
    print("=" * 50)
    
    # Create a dBase IV file
    fields = [
        DBFColumn(name="ID", field_type="N", length=5, decimals=0),
        DBFColumn(name="NAME", field_type="C", length=30, decimals=0)
    ]
    
    header = DBFHeader()
    header.fields = fields
    header.field_count = len(fields)
    header.version = 0x04  # dBase IV
    
    filename = "demo_lang"
    dbf = dbf_file_create(filename, header)
    
    # Get initial language driver
    lang = dbf_file_get_language_driver(dbf)
    print(f"\nInitial language driver: {lang} (US)")
    
    # Change to Western Europe
    dbf_file_set_language_driver(dbf, DBF_LANG_WESTERN_EUROPE)
    lang = dbf_file_get_language_driver(dbf)
    print(f"Changed to: {lang} (Western Europe)")
    
    # Change to Japan
    dbf_file_set_language_driver(dbf, DBF_LANG_JAPAN)
    lang = dbf_file_get_language_driver(dbf)
    print(f"Changed to: {lang} (Japan)")
    
    # Close and reopen
    dbf_file_close(dbf)
    dbf = dbf_file_open(filename)
    
    # Verify language driver persisted
    lang = dbf_file_get_language_driver(dbf)
    print(f"After reopen: {lang} (Japan)")
    
    dbf_file_close(dbf)
    
    # Test with dBase III
    print("\n" + "-" * 50)
    print("dBase III test:")
    
    filename_db3 = "demo_lang_db3"
    dbf = dbf_file_create_dbase3(filename_db3, header)
    
    lang = dbf_file_get_language_driver(dbf)
    print(f"dBase III language driver: {lang} (should be 0)")
    
    dbf_file_close(dbf)
    
    # Cleanup
    if os.path.exists(filename + ".DBF"):
        os.remove(filename + ".DBF")
    if os.path.exists(filename_db3 + ".DBF"):
        os.remove(filename_db3 + ".DBF")
    
    print("\nDemo completed successfully!")


if __name__ == "__main__":
    # Run the demo
    demo_language_driver_functions()
    
    # Run the tests
    print("\n" + "=" * 50)
    print("Running unit tests...")
    print("=" * 50)
    unittest.main()
