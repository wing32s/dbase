"""
Test file for DBF date functions.
This demonstrates how to get and set the last update date in DBF files.
"""

import os
import datetime
import unittest
from dbf_module import (
    DBFColumn, DBFHeader, DBFFile,
    dbf_file_create, dbf_file_create_dbase3, dbf_file_close, dbf_file_open,
    dbf_file_get_date, dbf_file_set_date
)


class TestDBFDate(unittest.TestCase):
    """Test cases for DBF date functions."""
    
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
    
    def test_get_date_on_create(self):
        """Test getting the date from a newly created file."""
        # Define test fields
        fields = [
            DBFColumn(name="ID", field_type="N", length=5, decimals=0),
            DBFColumn(name="NAME", field_type="C", length=30, decimals=0)
        ]
        
        # Create header with specific date
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        header.year = 126  # 2026
        header.month = 1
        header.day = 20
        
        # Create the file
        filename = "test_date_get"
        dbf = dbf_file_create_dbase3(filename, header)
        
        # Get the date
        year, month, day = dbf_file_get_date(dbf)
        
        # Verify the date
        self.assertEqual(year, 126)
        self.assertEqual(month, 1)
        self.assertEqual(day, 20)
        
        # Close the file
        dbf_file_close(dbf)
        
        # Add to cleanup list
        self.test_files.append(filename + ".DBF")
    
    def test_set_date(self):
        """Test setting the date in a DBF file."""
        # Define test fields
        fields = [
            DBFColumn(name="ID", field_type="N", length=5, decimals=0),
            DBFColumn(name="NAME", field_type="C", length=30, decimals=0)
        ]
        
        # Create header with initial date
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        header.year = 120  # 2020
        header.month = 1
        header.day = 1
        
        # Create the file
        filename = "test_date_set"
        dbf = dbf_file_create_dbase3(filename, header)
        
        # Set a new date
        dbf_file_set_date(dbf, 126, 1, 20)  # 2026-01-20
        
        # Get the date to verify
        year, month, day = dbf_file_get_date(dbf)
        self.assertEqual(year, 126)
        self.assertEqual(month, 1)
        self.assertEqual(day, 20)
        
        # Close the file
        dbf_file_close(dbf)
        
        # Add to cleanup list
        self.test_files.append(filename + ".DBF")
        
        # Reopen the file and verify the date was persisted
        dbf = dbf_file_open(filename)
        year, month, day = dbf_file_get_date(dbf)
        self.assertEqual(year, 126)
        self.assertEqual(month, 1)
        self.assertEqual(day, 20)
        
        dbf_file_close(dbf)
    
    def test_set_date_with_current_date(self):
        """Test setting the date to the current date."""
        # Define test fields
        fields = [
            DBFColumn(name="ID", field_type="N", length=5, decimals=0),
            DBFColumn(name="NAME", field_type="C", length=30, decimals=0)
        ]
        
        # Create header
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        
        # Create the file
        filename = "test_date_current"
        dbf = dbf_file_create_dbase3(filename, header)
        
        # Set to current date
        now = datetime.datetime.now()
        dbf_file_set_date(dbf, now.year - 1900, now.month, now.day)
        
        # Get the date to verify
        year, month, day = dbf_file_get_date(dbf)
        self.assertEqual(year, now.year - 1900)
        self.assertEqual(month, now.month)
        self.assertEqual(day, now.day)
        
        # Close the file
        dbf_file_close(dbf)
        
        # Add to cleanup list
        self.test_files.append(filename + ".DBF")
    
    def test_get_date_from_opened_file(self):
        """Test getting the date from an opened file."""
        # Define test fields
        fields = [
            DBFColumn(name="ID", field_type="N", length=5, decimals=0),
            DBFColumn(name="NAME", field_type="C", length=30, decimals=0)
        ]
        
        # Create header with specific date
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        header.year = 125  # 2025
        header.month = 12
        header.day = 31
        
        # Create the file
        filename = "test_date_open"
        dbf = dbf_file_create_dbase3(filename, header)
        dbf_file_close(dbf)
        
        # Add to cleanup list
        self.test_files.append(filename + ".DBF")
        
        # Open the file
        dbf = dbf_file_open(filename)
        
        # Get the date
        year, month, day = dbf_file_get_date(dbf)
        
        # Verify the date
        self.assertEqual(year, 125)
        self.assertEqual(month, 12)
        self.assertEqual(day, 31)
        
        # Close the file
        dbf_file_close(dbf)


def demo_date_functions():
    """Demonstrate the date functions."""
    print("DBF Date Functions Demo")
    print("=" * 50)
    
    # Create a sample file
    fields = [
        DBFColumn(name="ID", field_type="N", length=5, decimals=0),
        DBFColumn(name="NAME", field_type="C", length=30, decimals=0)
    ]
    
    header = DBFHeader()
    header.fields = fields
    header.field_count = len(fields)
    
    # Set initial date
    header.year = 120  # 2020
    header.month = 1
    header.day = 1
    
    filename = "demo_date"
    dbf = dbf_file_create_dbase3(filename, header)
    
    # Get initial date
    year, month, day = dbf_file_get_date(dbf)
    print(f"\nInitial date: {year + 1900}-{month:02d}-{day:02d}")
    
    # Update to current date
    now = datetime.datetime.now()
    dbf_file_set_date(dbf, now.year - 1900, now.month, now.day)
    
    # Get updated date
    year, month, day = dbf_file_get_date(dbf)
    print(f"Updated date: {year + 1900}-{month:02d}-{day:02d}")
    
    # Close and reopen
    dbf_file_close(dbf)
    dbf = dbf_file_open(filename)
    
    # Verify date persisted
    year, month, day = dbf_file_get_date(dbf)
    print(f"Date after reopen: {year + 1900}-{month:02d}-{day:02d}")
    
    dbf_file_close(dbf)
    
    # Cleanup
    if os.path.exists(filename + ".DBF"):
        os.remove(filename + ".DBF")
    
    print("\nDemo completed successfully!")


if __name__ == "__main__":
    # Run the demo
    demo_date_functions()
    
    # Run the tests
    print("\n" + "=" * 50)
    print("Running unit tests...")
    print("=" * 50)
    unittest.main()
