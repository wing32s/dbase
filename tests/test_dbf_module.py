"""
Test file for the dbf_module.py implementation.
This demonstrates how to create a DBF file using the module.
"""

import os
import datetime
from dbf_module import (
    DBFColumn, DBFHeader, DBFFile,
    dbf_file_create, dbf_file_create_dbase3, dbf_file_close, dbf_file_open,
    dbf_file_get_date, dbf_file_set_date,
    dbf_file_get_language_driver, dbf_file_set_language_driver,
    DBF_LANG_US, DBF_LANG_WESTERN_EUROPE, DBF_LANG_JAPAN
)


def create_sample_dbf():
    """Create a sample DBF file with some fields."""
    print("Creating sample DBF file...")
    
    # Define the fields for our DBF file
    fields = [
        DBFColumn(name="ID", field_type="N", length=5, decimals=0),
        DBFColumn(name="NAME", field_type="C", length=30, decimals=0),
        DBFColumn(name="BIRTHDATE", field_type="D", length=8, decimals=0),
        DBFColumn(name="SALARY", field_type="N", length=10, decimals=2),
        DBFColumn(name="ACTIVE", field_type="L", length=1, decimals=0),
        DBFColumn(name="NOTES", field_type="M", length=10, decimals=0)  # Memo field
    ]
    
    # Create a header with these fields
    header = DBFHeader()
    header.fields = fields
    header.field_count = len(fields)
    
    # Set the current date
    now = datetime.datetime.now()
    header.year = now.year - 1900  # dBase stores years since 1900
    header.month = now.month
    header.day = now.day
    
    # Create the DBF file
    dbf = dbf_file_create("sample", header)
    
    # Close the file
    dbf_file_close(dbf)
    
    print(f"DBF file created with {len(fields)} fields.")
    print(f"Header size: {header.header_size} bytes")
    print(f"Record size: {header.record_size} bytes")
    
    # Check if files were created
    if os.path.exists("sample.DBF"):
        print("sample.DBF created successfully.")
        print(f"File size: {os.path.getsize('sample.DBF')} bytes")
    
    if os.path.exists("sample.DBT"):
        print("sample.DBT (memo file) created successfully.")
        print(f"File size: {os.path.getsize('sample.DBT')} bytes")


def create_dbase3_file():
    """Create a dBase III file."""
    print("\nCreating dBase III file...")
    
    # Define the fields for our DBF file (no memo fields for dBase III)
    fields = [
        DBFColumn(name="ID", field_type="N", length=5, decimals=0),
        DBFColumn(name="NAME", field_type="C", length=30, decimals=0),
        DBFColumn(name="ACTIVE", field_type="L", length=1, decimals=0)
    ]
    
    # Create a header with these fields
    header = DBFHeader()
    header.fields = fields
    header.field_count = len(fields)
    
    # Set the current date
    now = datetime.datetime.now()
    header.year = now.year - 1900
    header.month = now.month
    header.day = now.day
    
    # Create the DBF file
    dbf = dbf_file_create_dbase3("sample_dbase3", header)
    
    # Close the file
    dbf_file_close(dbf)
    
    print(f"dBase III file created with {len(fields)} fields.")
    print(f"Header size: {header.header_size} bytes")
    print(f"Record size: {header.record_size} bytes")
    
    # Check if file was created
    if os.path.exists("sample_dbase3.DBF"):
        print("sample_dbase3.DBF created successfully.")
        print(f"File size: {os.path.getsize('sample_dbase3.DBF')} bytes")


def open_and_display_dbf(filename):
    """Open an existing DBF file and display its structure."""
    print(f"\nOpening DBF file: {filename}")
    try:
        # Open the DBF file
        dbf = dbf_file_open(filename)
        
        # Display header information
        print(f"File version: 0x{dbf.header.version:02X}")
        print(f"Last update: {dbf.header.year+1900}-{dbf.header.month:02d}-{dbf.header.day:02d}")
        print(f"Record count: {dbf.header.record_count}")
        print(f"Header size: {dbf.header.header_size} bytes")
        print(f"Record size: {dbf.header.record_size} bytes")
        
        # Display field information
        print(f"\nFields ({dbf.header.field_count}):\n")
        print(f"{'Name':<12} {'Type':<5} {'Length':<7} {'Decimals':<9} {'Offset':<6}")
        print("-" * 45)
        
        for field in dbf.header.fields:
            print(f"{field.name:<12} {field.field_type:<5} {field.length:<7} {field.decimals:<9} {field.offset:<6}")
        
        # Close the file
        dbf_file_close(dbf)
        print("\nFile closed successfully.")
        
    except Exception as e:
        print(f"Error: {str(e)}")


def test_date_functions():
    """Test getting and setting dates."""
    print("\nTesting date functions...")
    
    # Create a test file
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
    
    filename = "test_date"
    dbf = dbf_file_create_dbase3(filename, header)
    
    # Get initial date
    year, month, day = dbf_file_get_date(dbf)
    print(f"Initial date: {year + 1900}-{month:02d}-{day:02d}")
    
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
    
    print("Date functions test completed!")


def test_language_driver_functions():
    """Test getting and setting language driver."""
    print("\nTesting language driver functions...")
    
    # Create a dBase IV test file
    fields = [
        DBFColumn(name="ID", field_type="N", length=5, decimals=0),
        DBFColumn(name="NAME", field_type="C", length=30, decimals=0)
    ]
    
    header = DBFHeader()
    header.fields = fields
    header.field_count = len(fields)
    header.version = 0x04  # dBase IV
    
    filename = "test_lang"
    dbf = dbf_file_create(filename, header)
    
    # Get initial language driver
    lang = dbf_file_get_language_driver(dbf)
    print(f"Initial language driver: {lang} (US)")
    
    # Change to Western Europe
    dbf_file_set_language_driver(dbf, DBF_LANG_WESTERN_EUROPE)
    lang = dbf_file_get_language_driver(dbf)
    print(f"Changed to: {lang} (Western Europe)")
    
    # Close and reopen
    dbf_file_close(dbf)
    dbf = dbf_file_open(filename)
    
    # Verify language driver persisted
    lang = dbf_file_get_language_driver(dbf)
    print(f"After reopen: {lang} (Western Europe)")
    
    dbf_file_close(dbf)
    
    # Cleanup
    if os.path.exists(filename + ".DBF"):
        os.remove(filename + ".DBF")
    
    print("Language driver functions test completed!")


if __name__ == "__main__":
    # Create sample files
    create_sample_dbf()
    create_dbase3_file()
    
    # Open and display the created files
    open_and_display_dbf("sample")
    open_and_display_dbf("sample_dbase3")
    
    # Test date functions
    test_date_functions()
    
    # Test language driver functions
    test_language_driver_functions()
    
    # Cleanup demo files (unless KEEP_TEST_FILES is set)
    if not os.environ.get('KEEP_TEST_FILES'):
        print("\n🗑️  Cleaning up demo files...")
        for filename in ["sample", "sample_dbase3"]:
            for ext in [".DBF", ".DBT"]:
                filepath = filename + ext
                if os.path.exists(filepath):
                    try:
                        os.remove(filepath)
                        print(f"   Removed {filepath}")
                    except Exception as e:
                        print(f"   ⚠️  Could not remove {filepath}: {e}")
    else:
        print("\n📁 Keeping demo files (KEEP_TEST_FILES is set)")
