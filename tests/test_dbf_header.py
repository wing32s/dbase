"""
Test file for validating the binary format of DBF headers.
This ensures our implementation correctly follows the dBase file format specifications.
"""

import os
import datetime
import struct
import unittest
from dbf_module import (
    DBFColumn, DBFHeader, DBFFile,
    dbf_file_create, dbf_file_create_dbase3, dbf_file_close, dbf_file_open
)


class DBFHeaderValidator:
    """Utility class to validate DBF file headers."""
    
    @staticmethod
    def read_binary_header(filename):
        """Read the binary header from a DBF file."""
        if not filename.upper().endswith('.DBF'):
            filename = filename + '.DBF'
            
        with open(filename, 'rb') as f:
            # Read main header (32 bytes)
            header_bytes = f.read(32)
            
            # Read field descriptors until terminator (0x0D)
            field_descriptors = []
            while True:
                peek_byte = f.read(1)
                if not peek_byte or peek_byte[0] == 0x0D:
                    break
                    
                f.seek(f.tell() - 1)  # Rewind
                field_descriptors.append(f.read(32))
                
            # Read terminator (field descriptor terminator 0x0D)
            terminator = peek_byte
            
            return {
                'header_bytes': header_bytes,
                'field_descriptors': field_descriptors,
                'terminator': terminator
            }
    
    @staticmethod
    def validate_dbase3_header(header_bytes, expected_fields_count):
        """Validate a dBase III header."""
        # Version byte should be 0x03 for dBase III
        assert header_bytes[0] == 0x03, f"Expected version 0x03, got 0x{header_bytes[0]:02X}"
        
        # Extract record count (bytes 4-7, little endian)
        record_count = struct.unpack("<L", header_bytes[4:8])[0]
        assert record_count == 0, f"Expected record count 0, got {record_count}"
        
        # Extract header size (bytes 8-9, little endian)
        header_size = struct.unpack("<H", header_bytes[8:10])[0]
        expected_header_size = 32 + (expected_fields_count * 32) + 1
        assert header_size == expected_header_size, f"Expected header size {expected_header_size}, got {header_size}"
        
        # TableFlags should be 0 (unused) for dBase III
        assert header_bytes[28] == 0, f"Expected table flags 0, got {header_bytes[28]}"
        
        # LanguageDriver should be 0 (unused) for dBase III
        assert header_bytes[29] == 0, f"Expected language driver 0, got {header_bytes[29]}"
        
        return True
    
    @staticmethod
    def validate_dbase4_header(header_bytes, expected_fields_count):
        """Validate a dBase IV header."""
        # Version byte should be 0x04 for dBase IV without memo
        assert header_bytes[0] == 0x04, f"Expected version 0x04, got 0x{header_bytes[0]:02X}"
        
        # Extract record count (bytes 4-7, little endian)
        record_count = struct.unpack("<L", header_bytes[4:8])[0]
        assert record_count == 0, f"Expected record count 0, got {record_count}"
        
        # Extract header size (bytes 8-9, little endian)
        header_size = struct.unpack("<H", header_bytes[8:10])[0]
        expected_header_size = 32 + (expected_fields_count * 32) + 1
        assert header_size == expected_header_size, f"Expected header size {expected_header_size}, got {header_size}"
        
        # TableFlags should be 0 for dBase IV
        assert header_bytes[28] == 0, f"Expected table flags 0, got {header_bytes[28]}"
        
        # LanguageDriver should be DBF_LANG_US (1) for dBase IV by default
        assert header_bytes[29] == 1, f"Expected language driver 1, got {header_bytes[29]}"
        
        return True
    
    @staticmethod
    def validate_field_descriptor(field_bytes, expected_name, expected_type, expected_length, expected_decimals):
        """Validate a field descriptor."""
        # Extract field name (up to 11 bytes, null-terminated)
        field_name = ""
        for i in range(11):
            if field_bytes[i] != 0:
                field_name += chr(field_bytes[i])
        
        assert field_name == expected_name, f"Expected field name '{expected_name}', got '{field_name}'"
        
        # Field type (byte 11)
        field_type = chr(field_bytes[11])
        assert field_type == expected_type, f"Expected field type '{expected_type}', got '{field_type}'"
        
        # Field length (byte 16)
        field_length = field_bytes[16]
        assert field_length == expected_length, f"Expected field length {expected_length}, got {field_length}"
        
        # Field decimals (byte 17)
        field_decimals = field_bytes[17]
        assert field_decimals == expected_decimals, f"Expected field decimals {expected_decimals}, got {field_decimals}"
        
        return True


class TestDBFHeaders(unittest.TestCase):
    """Test cases for DBF header validation."""
    
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
    
    def test_dbase3_header(self):
        """Test dBase III header format."""
        # Define test fields
        fields = [
            DBFColumn(name="ID", field_type="N", length=5, decimals=0),
            DBFColumn(name="NAME", field_type="C", length=30, decimals=0),
            DBFColumn(name="ACTIVE", field_type="L", length=1, decimals=0)
        ]
        
        # Create header
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        
        # Set date
        now = datetime.datetime.now()
        header.year = now.year - 1900
        header.month = now.month
        header.day = now.day
        
        # Create the file
        filename = "test_dbase3"
        dbf = dbf_file_create_dbase3(filename, header)
        dbf_file_close(dbf)
        
        # Add to cleanup list
        self.test_files.append(filename + ".DBF")
        
        # Read and validate header
        binary_header = DBFHeaderValidator.read_binary_header(filename)
        
        # Validate main header
        self.assertTrue(
            DBFHeaderValidator.validate_dbase3_header(
                binary_header['header_bytes'], 
                len(fields)
            )
        )
        
        # Validate field descriptors
        self.assertEqual(len(binary_header['field_descriptors']), len(fields))
        
        # Check ID field
        self.assertTrue(
            DBFHeaderValidator.validate_field_descriptor(
                binary_header['field_descriptors'][0],
                "ID", "N", 5, 0
            )
        )
        
        # Check NAME field
        self.assertTrue(
            DBFHeaderValidator.validate_field_descriptor(
                binary_header['field_descriptors'][1],
                "NAME", "C", 30, 0
            )
        )
        
        # Check ACTIVE field
        self.assertTrue(
            DBFHeaderValidator.validate_field_descriptor(
                binary_header['field_descriptors'][2],
                "ACTIVE", "L", 1, 0
            )
        )
        
        # Check terminator (should be 0x0D for field descriptor terminator)
        self.assertEqual(binary_header['terminator'], b'\r')  # \r is 0x0D
    
    def test_dbase4_header(self):
        """Test dBase IV header format."""
        # Define test fields
        fields = [
            DBFColumn(name="ID", field_type="N", length=5, decimals=0),
            DBFColumn(name="NAME", field_type="C", length=30, decimals=0),
            DBFColumn(name="SALARY", field_type="N", length=10, decimals=2),
            DBFColumn(name="ACTIVE", field_type="L", length=1, decimals=0)
        ]
        
        # Create header
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        header.version = 0x04  # Force dBase IV
        
        # Set date
        now = datetime.datetime.now()
        header.year = now.year - 1900
        header.month = now.month
        header.day = now.day
        
        # Create the file
        filename = "test_dbase4"
        dbf = dbf_file_create(filename, header)
        dbf_file_close(dbf)
        
        # Add to cleanup list
        self.test_files.append(filename + ".DBF")
        
        # Read and validate header
        binary_header = DBFHeaderValidator.read_binary_header(filename)
        
        # Validate main header
        self.assertTrue(
            DBFHeaderValidator.validate_dbase4_header(
                binary_header['header_bytes'], 
                len(fields)
            )
        )
        
        # Validate field descriptors
        self.assertEqual(len(binary_header['field_descriptors']), len(fields))
        
        # Check ID field
        self.assertTrue(
            DBFHeaderValidator.validate_field_descriptor(
                binary_header['field_descriptors'][0],
                "ID", "N", 5, 0
            )
        )
        
        # Check NAME field
        self.assertTrue(
            DBFHeaderValidator.validate_field_descriptor(
                binary_header['field_descriptors'][1],
                "NAME", "C", 30, 0
            )
        )
        
        # Check SALARY field
        self.assertTrue(
            DBFHeaderValidator.validate_field_descriptor(
                binary_header['field_descriptors'][2],
                "SALARY", "N", 10, 2
            )
        )
        
        # Check ACTIVE field
        self.assertTrue(
            DBFHeaderValidator.validate_field_descriptor(
                binary_header['field_descriptors'][3],
                "ACTIVE", "L", 1, 0
            )
        )
        
        # Check terminator (should be 0x0D for field descriptor terminator)
        self.assertEqual(binary_header['terminator'], b'\r')  # \r is 0x0D
    
    def test_dbase5_with_memo(self):
        """Test dBase V header format with memo fields."""
        # Define test fields
        fields = [
            DBFColumn(name="ID", field_type="N", length=5, decimals=0),
            DBFColumn(name="NAME", field_type="C", length=30, decimals=0),
            DBFColumn(name="NOTES", field_type="M", length=10, decimals=0)  # Memo field
        ]
        
        # Create header
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        
        # Set date
        now = datetime.datetime.now()
        header.year = now.year - 1900
        header.month = now.month
        header.day = now.day
        
        # Create the file
        filename = "test_dbase5"
        dbf = dbf_file_create(filename, header)
        dbf_file_close(dbf)
        
        # Add to cleanup list
        self.test_files.append(filename + ".DBF")
        
        # Read and validate header
        binary_header = DBFHeaderValidator.read_binary_header(filename)
        
        # Version byte should be 0x05 for dBase V with memo
        self.assertEqual(binary_header['header_bytes'][0], 0x05)
        
        # Validate field descriptors
        self.assertEqual(len(binary_header['field_descriptors']), len(fields))
        
        # Check NOTES field (memo)
        self.assertTrue(
            DBFHeaderValidator.validate_field_descriptor(
                binary_header['field_descriptors'][2],
                "NOTES", "M", 10, 0
            )
        )
        
        # Check that memo file was created
        self.assertTrue(os.path.exists(filename + ".DBT"))
        
    def test_create_and_open(self):
        """Test creating a file and then opening it."""
        # Define test fields
        fields = [
            DBFColumn(name="ID", field_type="N", length=5, decimals=0),
            DBFColumn(name="NAME", field_type="C", length=30, decimals=0),
            DBFColumn(name="ACTIVE", field_type="L", length=1, decimals=0)
        ]
        
        # Create header
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        
        # Set date
        now = datetime.datetime.now()
        header.year = now.year - 1900
        header.month = now.month
        header.day = now.day
        
        # Create the file
        filename = "test_create_open"
        dbf = dbf_file_create_dbase3(filename, header)
        dbf_file_close(dbf)
        
        # Add to cleanup list
        self.test_files.append(filename + ".DBF")
        
        # Now open the file and verify its contents
        dbf = dbf_file_open(filename)
        
        # Verify header information
        self.assertEqual(dbf.header.version, 0x03)
        self.assertEqual(dbf.header.record_count, 0)
        self.assertEqual(dbf.header.field_count, len(fields))
        self.assertEqual(dbf.header.language_driver, 0)  # Should be 0 for dBase III
        
        # Verify field information
        self.assertEqual(len(dbf.header.fields), len(fields))
        self.assertEqual(dbf.header.fields[0].name, "ID")
        self.assertEqual(dbf.header.fields[0].field_type, "N")
        self.assertEqual(dbf.header.fields[0].length, 5)
        
        self.assertEqual(dbf.header.fields[1].name, "NAME")
        self.assertEqual(dbf.header.fields[1].field_type, "C")
        self.assertEqual(dbf.header.fields[1].length, 30)
        
        self.assertEqual(dbf.header.fields[2].name, "ACTIVE")
        self.assertEqual(dbf.header.fields[2].field_type, "L")
        self.assertEqual(dbf.header.fields[2].length, 1)
        
        # Close the file
        dbf_file_close(dbf)


if __name__ == "__main__":
    unittest.main()
