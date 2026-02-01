"""
Test file for binary validation of DBF field descriptors.
This performs byte-by-byte comparison of field descriptors and validates the header terminator.
"""

import os
import datetime
import struct
import unittest
from dbf_module import (
    DBFColumn, DBFHeader, DBFFile,
    dbf_file_create, dbf_file_create_dbase3, dbf_file_close
)


class TestDBFFieldBinary(unittest.TestCase):
    """Test cases for binary field descriptor validation."""
    
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
    
    def read_field_descriptor(self, file_handle):
        """Read a single field descriptor (32 bytes) from file."""
        descriptor = file_handle.read(32)
        if len(descriptor) != 32:
            return None
        
        # Parse the descriptor
        field_info = {
            'name_bytes': descriptor[0:11],
            'name': '',
            'type_byte': descriptor[11],
            'type': chr(descriptor[11]),
            'reserved1': descriptor[12:16],
            'length': descriptor[16],
            'decimals': descriptor[17],
            'reserved2': descriptor[18:32]
        }
        
        # Extract null-terminated name
        for i in range(11):
            if descriptor[i] == 0:
                break
            field_info['name'] += chr(descriptor[i])
        
        return field_info
    
    def test_single_field_binary(self):
        """Test binary format of a single field descriptor."""
        # Define a single field
        fields = [
            DBFColumn(name="ID", field_type="N", length=5, decimals=0)
        ]
        
        # Create header
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        
        # Create the file
        filename = "test_single_field"
        dbf = dbf_file_create_dbase3(filename, header)
        dbf_file_close(dbf)
        
        # Add to cleanup list
        self.test_files.append(filename + ".DBF")
        
        # Read and verify binary format
        with open(filename + ".DBF", "rb") as f:
            # Skip main header (32 bytes)
            f.seek(32)
            
            # Read field descriptor
            field_desc = self.read_field_descriptor(f)
            
            # Verify field name
            self.assertEqual(field_desc['name'], "ID")
            
            # Verify name is null-padded
            expected_name_bytes = b'ID' + b'\x00' * 9
            self.assertEqual(field_desc['name_bytes'], expected_name_bytes)
            
            # Verify field type
            self.assertEqual(field_desc['type'], "N")
            self.assertEqual(field_desc['type_byte'], ord('N'))
            
            # Verify length
            self.assertEqual(field_desc['length'], 5)
            
            # Verify decimals
            self.assertEqual(field_desc['decimals'], 0)
            
            # Read next byte - should be header terminator (0x0D)
            terminator = f.read(1)
            self.assertEqual(terminator, b'\x0D', "Header terminator should be 0x0D")
    
    def test_multiple_fields_binary(self):
        """Test binary format of multiple field descriptors."""
        # Define multiple fields
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
        
        # Create the file
        filename = "test_multi_fields"
        dbf = dbf_file_create_dbase3(filename, header)
        dbf_file_close(dbf)
        
        # Add to cleanup list
        self.test_files.append(filename + ".DBF")
        
        # Read and verify binary format
        with open(filename + ".DBF", "rb") as f:
            # Skip main header (32 bytes)
            f.seek(32)
            
            # Read and verify each field descriptor
            for i, expected_field in enumerate(fields):
                field_desc = self.read_field_descriptor(f)
                
                self.assertIsNotNone(field_desc, f"Field {i} should exist")
                self.assertEqual(field_desc['name'], expected_field.name)
                self.assertEqual(field_desc['type'], expected_field.field_type)
                self.assertEqual(field_desc['length'], expected_field.length)
                self.assertEqual(field_desc['decimals'], expected_field.decimals)
            
            # Read next byte - should be header terminator (0x0D)
            terminator = f.read(1)
            self.assertEqual(terminator, b'\x0D', "Header terminator should be 0x0D")
    
    def test_field_name_padding(self):
        """Test that field names are properly null-padded to 11 bytes."""
        # Define fields with various name lengths
        fields = [
            DBFColumn(name="A", field_type="C", length=10, decimals=0),           # 1 char
            DBFColumn(name="AB", field_type="C", length=10, decimals=0),          # 2 chars
            DBFColumn(name="ABCDEFGHIJK", field_type="C", length=10, decimals=0), # 11 chars (max)
        ]
        
        # Create header
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        
        # Create the file
        filename = "test_name_padding"
        dbf = dbf_file_create_dbase3(filename, header)
        dbf_file_close(dbf)
        
        # Add to cleanup list
        self.test_files.append(filename + ".DBF")
        
        # Read and verify binary format
        with open(filename + ".DBF", "rb") as f:
            # Skip main header (32 bytes)
            f.seek(32)
            
            # Field 1: "A" + 10 nulls
            field_desc = self.read_field_descriptor(f)
            expected_bytes = b'A' + b'\x00' * 10
            self.assertEqual(field_desc['name_bytes'], expected_bytes)
            
            # Field 2: "AB" + 9 nulls
            field_desc = self.read_field_descriptor(f)
            expected_bytes = b'AB' + b'\x00' * 9
            self.assertEqual(field_desc['name_bytes'], expected_bytes)
            
            # Field 3: "ABCDEFGHIJK" (exactly 11 chars, no nulls)
            field_desc = self.read_field_descriptor(f)
            expected_bytes = b'ABCDEFGHIJK'
            self.assertEqual(field_desc['name_bytes'], expected_bytes)
            
            # Verify terminator
            terminator = f.read(1)
            self.assertEqual(terminator, b'\x0D')
    
    def test_field_descriptor_size(self):
        """Test that each field descriptor is exactly 32 bytes."""
        # Define fields
        fields = [
            DBFColumn(name="FIELD1", field_type="C", length=20, decimals=0),
            DBFColumn(name="FIELD2", field_type="N", length=8, decimals=2)
        ]
        
        # Create header
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        
        # Create the file
        filename = "test_descriptor_size"
        dbf = dbf_file_create_dbase3(filename, header)
        dbf_file_close(dbf)
        
        # Add to cleanup list
        self.test_files.append(filename + ".DBF")
        
        # Read and verify sizes
        with open(filename + ".DBF", "rb") as f:
            # Skip main header (32 bytes)
            f.seek(32)
            
            # Read each field descriptor and verify size
            for i in range(len(fields)):
                start_pos = f.tell()
                descriptor = f.read(32)
                end_pos = f.tell()
                
                self.assertEqual(len(descriptor), 32, f"Field descriptor {i} should be 32 bytes")
                self.assertEqual(end_pos - start_pos, 32, f"Field descriptor {i} should advance 32 bytes")
    
    def test_header_terminator_position(self):
        """Test that header terminator (0x0D) is at the correct position."""
        # Define fields
        fields = [
            DBFColumn(name="ID", field_type="N", length=5, decimals=0),
            DBFColumn(name="NAME", field_type="C", length=30, decimals=0),
            DBFColumn(name="ACTIVE", field_type="L", length=1, decimals=0)
        ]
        
        # Create header
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        
        # Create the file
        filename = "test_terminator_pos"
        dbf = dbf_file_create_dbase3(filename, header)
        dbf_file_close(dbf)
        
        # Add to cleanup list
        self.test_files.append(filename + ".DBF")
        
        # Calculate expected terminator position
        # 32 bytes (main header) + (num_fields * 32 bytes per field)
        expected_terminator_pos = 32 + (len(fields) * 32)
        
        # Read and verify
        with open(filename + ".DBF", "rb") as f:
            f.seek(expected_terminator_pos)
            terminator = f.read(1)
            
            self.assertEqual(terminator, b'\x0D', 
                           f"Byte at position {expected_terminator_pos} should be 0x0D")
            
            # Verify the byte after terminator is 0x1A (end of file marker)
            eof_marker = f.read(1)
            self.assertEqual(eof_marker, b'\x1A',
                           f"Byte after terminator should be 0x1A (EOF marker)")
    
    def test_field_type_bytes(self):
        """Test that field type bytes are correctly set."""
        # Define fields with different types
        fields = [
            DBFColumn(name="CHAR_FLD", field_type="C", length=10, decimals=0),
            DBFColumn(name="NUM_FLD", field_type="N", length=8, decimals=2),
            DBFColumn(name="LOG_FLD", field_type="L", length=1, decimals=0),
            DBFColumn(name="DATE_FLD", field_type="D", length=8, decimals=0),
            DBFColumn(name="MEMO_FLD", field_type="M", length=10, decimals=0)
        ]
        
        # Create header
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        
        # Create the file
        filename = "test_field_types"
        dbf = dbf_file_create(filename, header)
        dbf_file_close(dbf)
        
        # Add to cleanup list
        self.test_files.append(filename + ".DBF")
        
        # Read and verify field types
        with open(filename + ".DBF", "rb") as f:
            # Skip main header (32 bytes)
            f.seek(32)
            
            expected_types = ['C', 'N', 'L', 'D', 'M']
            
            for i, expected_type in enumerate(expected_types):
                field_desc = self.read_field_descriptor(f)
                
                self.assertEqual(field_desc['type'], expected_type,
                               f"Field {i} type should be '{expected_type}'")
                self.assertEqual(field_desc['type_byte'], ord(expected_type),
                               f"Field {i} type byte should be {ord(expected_type)}")
    
    def test_complete_header_structure(self):
        """Test the complete header structure including all components."""
        # Define fields
        fields = [
            DBFColumn(name="ID", field_type="N", length=5, decimals=0),
            DBFColumn(name="NAME", field_type="C", length=30, decimals=0)
        ]
        
        # Create header
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        header.year = 126  # 2026
        header.month = 1
        header.day = 20
        
        # Create the file
        filename = "test_complete_header"
        dbf = dbf_file_create_dbase3(filename, header)
        dbf_file_close(dbf)
        
        # Add to cleanup list
        self.test_files.append(filename + ".DBF")
        
        # Read and verify complete structure
        with open(filename + ".DBF", "rb") as f:
            # Read main header (32 bytes)
            main_header = f.read(32)
            
            # Verify version byte
            self.assertEqual(main_header[0], 0x03, "Version should be 0x03")
            
            # Verify date
            self.assertEqual(main_header[1], 126, "Year should be 126")
            self.assertEqual(main_header[2], 1, "Month should be 1")
            self.assertEqual(main_header[3], 20, "Day should be 20")
            
            # Verify record count (should be 0 for new file)
            record_count = struct.unpack("<L", main_header[4:8])[0]
            self.assertEqual(record_count, 0, "Record count should be 0")
            
            # Verify header size
            # 32 (main) + (2 fields * 32) + 1 (terminator) = 97
            header_size = struct.unpack("<H", main_header[8:10])[0]
            self.assertEqual(header_size, 97, "Header size should be 97")
            
            # Verify record size
            # 1 (delete flag) + 5 (ID) + 30 (NAME) = 36
            record_size = struct.unpack("<H", main_header[10:12])[0]
            self.assertEqual(record_size, 36, "Record size should be 36")
            
            # Read field descriptors
            for i in range(len(fields)):
                field_desc = self.read_field_descriptor(f)
                self.assertIsNotNone(field_desc)
            
            # Verify terminator
            terminator = f.read(1)
            self.assertEqual(terminator, b'\x0D', "Header terminator should be 0x0D")
            
            # Verify EOF marker
            eof_marker = f.read(1)
            self.assertEqual(eof_marker, b'\x1A', "EOF marker should be 0x1A")


def demo_field_binary_structure():
    """Demonstrate the binary structure of field descriptors."""
    print("DBF Field Descriptor Binary Structure Demo")
    print("=" * 60)
    
    # Create a simple file
    fields = [
        DBFColumn(name="ID", field_type="N", length=5, decimals=0),
        DBFColumn(name="NAME", field_type="C", length=30, decimals=0)
    ]
    
    header = DBFHeader()
    header.fields = fields
    header.field_count = len(fields)
    
    filename = "demo_binary"
    dbf = dbf_file_create_dbase3(filename, header)
    dbf_file_close(dbf)
    
    # Read and display binary structure
    with open(filename + ".DBF", "rb") as f:
        print("\nMain Header (32 bytes):")
        main_header = f.read(32)
        print(f"  Version: 0x{main_header[0]:02X}")
        print(f"  Date: {main_header[1]}/{main_header[2]}/{main_header[3]}")
        print(f"  Record Count: {struct.unpack('<L', main_header[4:8])[0]}")
        print(f"  Header Size: {struct.unpack('<H', main_header[8:10])[0]}")
        print(f"  Record Size: {struct.unpack('<H', main_header[10:12])[0]}")
        
        print("\nField Descriptors:")
        for i in range(len(fields)):
            print(f"\n  Field {i+1} (32 bytes):")
            descriptor = f.read(32)
            
            # Extract name
            name = ""
            for j in range(11):
                if descriptor[j] == 0:
                    break
                name += chr(descriptor[j])
            
            print(f"    Name: '{name}' (bytes 0-10)")
            print(f"    Type: '{chr(descriptor[11])}' (byte 11)")
            print(f"    Length: {descriptor[16]} (byte 16)")
            print(f"    Decimals: {descriptor[17]} (byte 17)")
            
            # Show hex dump of name bytes
            name_hex = ' '.join(f'{b:02X}' for b in descriptor[0:11])
            print(f"    Name bytes (hex): {name_hex}")
        
        print("\nHeader Terminator:")
        terminator = f.read(1)
        print(f"  Byte: 0x{terminator[0]:02X} (should be 0x0D)")
        
        print("\nEOF Marker:")
        eof = f.read(1)
        print(f"  Byte: 0x{eof[0]:02X} (should be 0x1A)")
    
    # Cleanup
    if os.path.exists(filename + ".DBF"):
        os.remove(filename + ".DBF")
    
    print("\nDemo completed successfully!")


if __name__ == "__main__":
    # Run the demo
    demo_field_binary_structure()
    
    # Run the tests
    print("\n" + "=" * 60)
    print("Running unit tests...")
    print("=" * 60)
    unittest.main()
