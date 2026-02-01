"""
Test file for DBF memo field functionality.
This tests writing and reading text data in memo fields.
"""

import os
import unittest
from dbf_module import (
    DBFColumn, DBFHeader, DBFFile,
    dbf_file_create, dbf_file_close,
    dbf_memo_write, dbf_memo_write_buffer, dbf_memo_get_info,
    dbf_memo_read_small, dbf_memo_read_binary,
    dbf_memo_read_chunk, dbf_memo_read_buffer,
    DBF_MEMO_BLOCK_SIZE
)


class TestDBFMemo(unittest.TestCase):
    """Test cases for DBF memo functionality."""
    
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
            
            # Remove DBT file
            dbt_file = filename.replace('.DBF', '.DBT')
            if os.path.exists(dbt_file):
                try:
                    os.remove(dbt_file)
                except:
                    pass
    
    def test_create_database_with_memo_field(self):
        """Test creating a database with just a memo field."""
        # Create DBF with memo field
        fields = [
            DBFColumn(name="NOTES", field_type="M", length=10, decimals=0)
        ]
        
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        
        filename = "test_memo_only"
        dbf = dbf_file_create(filename, header)
        
        # Verify version is 0x05 (dBase V with memo)
        self.assertEqual(dbf.header.version, 0x05)
        
        dbf_file_close(dbf)
        
        # Add to cleanup list
        self.test_files.append(filename + ".DBF")
        
        # Verify DBF file was created
        self.assertTrue(os.path.exists(filename + ".DBF"))
        
        # Verify DBT file was created
        self.assertTrue(os.path.exists(filename + ".DBT"))
    
    def test_memo_write_and_read_small(self):
        """Test writing and reading a small memo."""
        # Create memo file
        memo_filename = "test_memo_write"
        self.test_files.append(memo_filename + ".DBT")
        
        # Write memo data
        test_text = "This is a test memo field with some text data."
        block_num = dbf_memo_write(memo_filename + ".DBT", 1, test_text)
        
        # Verify block number is valid
        self.assertGreater(block_num, 0)
        
        # Read memo data
        memo_type, read_text = dbf_memo_read_small(memo_filename + ".DBT", block_num)
        
        # Verify data matches
        self.assertEqual(memo_type, 1)
        self.assertEqual(read_text, test_text)
    
    def test_memo_write_multiple(self):
        """Test writing multiple memos to the same file."""
        memo_filename = "test_memo_multi"
        self.test_files.append(memo_filename + ".DBT")
        
        # Write first memo
        text1 = "First memo"
        block1 = dbf_memo_write(memo_filename + ".DBT", 1, text1)
        
        # Write second memo
        text2 = "Second memo with more text"
        block2 = dbf_memo_write(memo_filename + ".DBT", 1, text2)
        
        # Write third memo
        text3 = "Third memo"
        block3 = dbf_memo_write(memo_filename + ".DBT", 1, text3)
        
        # Verify block numbers are different and increasing
        self.assertNotEqual(block1, block2)
        self.assertNotEqual(block2, block3)
        self.assertLess(block1, block2)
        self.assertLess(block2, block3)
        
        # Read all memos and verify
        _, read_text1 = dbf_memo_read_small(memo_filename + ".DBT", block1)
        _, read_text2 = dbf_memo_read_small(memo_filename + ".DBT", block2)
        _, read_text3 = dbf_memo_read_small(memo_filename + ".DBT", block3)
        
        self.assertEqual(read_text1, text1)
        self.assertEqual(read_text2, text2)
        self.assertEqual(read_text3, text3)
    
    def test_memo_get_info(self):
        """Test getting memo information."""
        memo_filename = "test_memo_info"
        self.test_files.append(memo_filename + ".DBT")
        
        # Write memo
        test_text = "Test memo for info"
        block_num = dbf_memo_write(memo_filename + ".DBT", 1, test_text)
        
        # Get memo info
        memo_type, memo_len = dbf_memo_get_info(memo_filename + ".DBT", block_num)
        
        # Verify info
        self.assertEqual(memo_type, 1)
        self.assertEqual(memo_len, len(test_text.encode('utf-8')))
    
    def test_memo_read_chunk(self):
        """Test reading memo data in chunks."""
        memo_filename = "test_memo_chunk"
        self.test_files.append(memo_filename + ".DBT")
        
        # Write memo
        test_text = "This is a longer text that we will read in chunks."
        block_num = dbf_memo_write(memo_filename + ".DBT", 1, test_text)
        
        # Read first chunk
        success1, chunk1 = dbf_memo_read_chunk(memo_filename + ".DBT", block_num, 0, 10)
        self.assertTrue(success1)
        self.assertEqual(chunk1.decode('utf-8'), test_text[:10])
        
        # Read second chunk
        success2, chunk2 = dbf_memo_read_chunk(memo_filename + ".DBT", block_num, 10, 10)
        self.assertTrue(success2)
        self.assertEqual(chunk2.decode('utf-8'), test_text[10:20])
        
        # Read remaining
        success3, chunk3 = dbf_memo_read_chunk(memo_filename + ".DBT", block_num, 20, 100)
        self.assertTrue(success3)
        self.assertEqual(chunk3.decode('utf-8'), test_text[20:])
    
    def test_memo_read_buffer(self):
        """Test reading memo data into a buffer."""
        memo_filename = "test_memo_buffer"
        self.test_files.append(memo_filename + ".DBT")
        
        # Write memo
        test_text = "Test memo for buffer reading"
        block_num = dbf_memo_write(memo_filename + ".DBT", 1, test_text)
        
        # Read into buffer
        memo_type, data = dbf_memo_read_buffer(memo_filename + ".DBT", block_num, 1024)
        
        # Verify
        self.assertEqual(memo_type, 1)
        self.assertEqual(data.decode('utf-8'), test_text)
    
    def test_memo_empty_text(self):
        """Test writing and reading empty memo."""
        memo_filename = "test_memo_empty"
        self.test_files.append(memo_filename + ".DBT")
        
        # Write empty memo
        block_num = dbf_memo_write(memo_filename + ".DBT", 1, "")
        
        # Read empty memo
        memo_type, text = dbf_memo_read_small(memo_filename + ".DBT", block_num)
        
        # Verify
        self.assertEqual(memo_type, 1)
        self.assertEqual(text, "")
    
    def test_memo_unicode_text(self):
        """Test writing and reading Unicode text."""
        memo_filename = "test_memo_unicode"
        self.test_files.append(memo_filename + ".DBT")
        
        # Write Unicode text
        test_text = "Hello 世界 🌍 Привет"
        block_num = dbf_memo_write(memo_filename + ".DBT", 1, test_text)
        
        # Read Unicode text
        memo_type, read_text = dbf_memo_read_small(memo_filename + ".DBT", block_num)
        
        # Verify
        self.assertEqual(memo_type, 1)
        self.assertEqual(read_text, test_text)
    
    def test_memo_large_text(self):
        """Test writing and reading larger text (multiple blocks)."""
        memo_filename = "test_memo_large"
        self.test_files.append(memo_filename + ".DBT")
        
        # Create text larger than one block
        test_text = "A" * (DBF_MEMO_BLOCK_SIZE * 2)
        block_num = dbf_memo_write(memo_filename + ".DBT", 1, test_text)
        
        # Read large text
        memo_type, read_text = dbf_memo_read_small(memo_filename + ".DBT", block_num)
        
        # Verify
        self.assertEqual(memo_type, 1)
        self.assertEqual(read_text, test_text)
    
    def test_memo_invalid_block(self):
        """Test reading from invalid block number."""
        memo_filename = "test_memo_invalid"
        self.test_files.append(memo_filename + ".DBT")
        
        # Write a memo first
        dbf_memo_write(memo_filename + ".DBT", 1, "Test")
        
        # Try to read from invalid block
        memo_type, text = dbf_memo_read_small(memo_filename + ".DBT", 999)
        
        # Should return empty
        self.assertEqual(memo_type, 0)
        self.assertEqual(text, "")
    
    def test_memo_write_binary_buffer(self):
        """Test writing binary data using dbf_memo_write_buffer."""
        memo_filename = "test_memo_binary"
        self.test_files.append(memo_filename + ".DBT")
        
        # Create binary data (e.g., image-like data)
        binary_data = bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])  # PNG header
        binary_data += bytes(range(256))  # Add more binary data
        
        # Write binary data with type 2
        block_num = dbf_memo_write_buffer(memo_filename + ".DBT", 2, binary_data)
        
        # Verify block number
        self.assertGreater(block_num, 0)
        
        # Read binary data
        memo_type, read_data = dbf_memo_read_binary(memo_filename + ".DBT", block_num)
        
        # Verify data matches
        self.assertEqual(memo_type, 2)
        self.assertEqual(read_data, binary_data)
    
    def test_memo_binary_roundtrip(self):
        """Test binary data roundtrip."""
        memo_filename = "test_memo_bin_roundtrip"
        self.test_files.append(memo_filename + ".DBT")
        
        # Create various binary patterns
        test_data = bytearray()
        test_data.extend(b'\\x00' * 100)  # Nulls
        test_data.extend(b'\\xFF' * 100)  # All bits set
        test_data.extend(bytes(range(256)))  # All byte values
        
        # Write binary data
        block_num = dbf_memo_write_buffer(memo_filename + ".DBT", 2, bytes(test_data))
        
        # Read back
        memo_type, read_data = dbf_memo_read_binary(memo_filename + ".DBT", block_num)
        
        # Verify exact match
        self.assertEqual(memo_type, 2)
        self.assertEqual(read_data, bytes(test_data))
    
    def test_memo_binary_large(self):
        """Test large binary data spanning multiple blocks."""
        memo_filename = "test_memo_bin_large"
        self.test_files.append(memo_filename + ".DBT")
        
        # Create large binary data (3 blocks worth)
        binary_data = bytes(range(256)) * (DBF_MEMO_BLOCK_SIZE * 3 // 256)
        
        # Write binary data
        block_num = dbf_memo_write_buffer(memo_filename + ".DBT", 2, binary_data)
        
        # Read back
        memo_type, read_data = dbf_memo_read_binary(memo_filename + ".DBT", block_num, len(binary_data))
        
        # Verify
        self.assertEqual(memo_type, 2)
        self.assertEqual(len(read_data), len(binary_data))
        self.assertEqual(read_data, binary_data)
    
    def test_memo_mixed_text_and_binary(self):
        """Test writing both text and binary memos to same file."""
        memo_filename = "test_memo_mixed"
        self.test_files.append(memo_filename + ".DBT")
        
        # Write text memo
        text_data = "This is text data"
        text_block = dbf_memo_write(memo_filename + ".DBT", 1, text_data)
        
        # Write binary memo
        binary_data = bytes([0x00, 0x01, 0x02, 0xFF, 0xFE, 0xFD])
        binary_block = dbf_memo_write_buffer(memo_filename + ".DBT", 2, binary_data)
        
        # Verify blocks are different
        self.assertNotEqual(text_block, binary_block)
        
        # Read text memo
        memo_type1, read_text = dbf_memo_read_small(memo_filename + ".DBT", text_block)
        self.assertEqual(memo_type1, 1)
        self.assertEqual(read_text, text_data)
        
        # Read binary memo
        memo_type2, read_binary = dbf_memo_read_binary(memo_filename + ".DBT", binary_block)
        self.assertEqual(memo_type2, 2)
        self.assertEqual(read_binary, binary_data)
    
    def test_memo_binary_empty(self):
        """Test writing empty binary data."""
        memo_filename = "test_memo_bin_empty"
        self.test_files.append(memo_filename + ".DBT")
        
        # Write empty binary data
        block_num = dbf_memo_write_buffer(memo_filename + ".DBT", 2, b'')
        
        # Read back
        memo_type, read_data = dbf_memo_read_binary(memo_filename + ".DBT", block_num)
        
        # Verify
        self.assertEqual(memo_type, 2)
        self.assertEqual(read_data, b'')
    
    def test_memo_binary_with_embedded_nulls(self):
        """Test binary data with embedded null bytes."""
        memo_filename = "test_memo_bin_nulls"
        self.test_files.append(memo_filename + ".DBT")
        
        # Create data with embedded nulls
        binary_data = b'ABC\\x00\\x00\\x00DEF\\x00GHI'
        
        # Write binary data
        block_num = dbf_memo_write_buffer(memo_filename + ".DBT", 2, binary_data)
        
        # Read back
        memo_type, read_data = dbf_memo_read_binary(memo_filename + ".DBT", block_num)
        
        # Verify exact match including nulls
        self.assertEqual(memo_type, 2)
        self.assertEqual(read_data, binary_data)
        self.assertEqual(len(read_data), len(binary_data))


def demo_memo_functionality():
    """Demonstrate memo field functionality."""
    print("DBF Memo Field Demo")
    print("=" * 60)
    
    # Create a database with memo field
    fields = [
        DBFColumn(name="ID", field_type="N", length=5, decimals=0),
        DBFColumn(name="NOTES", field_type="M", length=10, decimals=0)
    ]
    
    header = DBFHeader()
    header.fields = fields
    header.field_count = len(fields)
    
    filename = "demo_memo"
    dbf = dbf_file_create(filename, header)
    
    print(f"\nCreated database: {filename}.DBF")
    print(f"  Version: 0x{dbf.header.version:02X} (dBase V with memo)")
    print(f"  Fields: {header.field_count}")
    print(f"  Memo file: {filename}.DBT")
    
    dbf_file_close(dbf)
    
    # Write some memo data
    print("\nWriting memo data...")
    
    memo1_text = "This is the first memo entry."
    block1 = dbf_memo_write(filename + ".DBT", 1, memo1_text)
    print(f"  Memo 1 written to block {block1}")
    
    memo2_text = "This is a longer second memo entry with more text to demonstrate the memo field functionality."
    block2 = dbf_memo_write(filename + ".DBT", 1, memo2_text)
    print(f"  Memo 2 written to block {block2}")
    
    # Read memo data
    print("\nReading memo data...")
    
    memo_type1, read_text1 = dbf_memo_read_small(filename + ".DBT", block1)
    print(f"  Memo 1 (block {block1}): \"{read_text1}\"")
    
    memo_type2, read_text2 = dbf_memo_read_small(filename + ".DBT", block2)
    print(f"  Memo 2 (block {block2}): \"{read_text2}\"")
    
    # Get memo info
    print("\nMemo information:")
    memo_type, memo_len = dbf_memo_get_info(filename + ".DBT", block1)
    print(f"  Memo 1: type={memo_type}, length={memo_len} bytes")
    
    memo_type, memo_len = dbf_memo_get_info(filename + ".DBT", block2)
    print(f"  Memo 2: type={memo_type}, length={memo_len} bytes")
    
    # Test binary data
    print("\n" + "-" * 60)
    print("Binary data test:")
    
    # Write binary data
    binary_data = bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])  # PNG header
    binary_data += bytes(range(32))  # Add some binary data
    
    block3 = dbf_memo_write_buffer(filename + ".DBT", 2, binary_data)
    print(f"  Binary data written to block {block3}")
    print(f"  Binary data size: {len(binary_data)} bytes")
    
    # Read binary data
    memo_type3, read_binary = dbf_memo_read_binary(filename + ".DBT", block3)
    print(f"  Binary data read: type={memo_type3}, size={len(read_binary)} bytes")
    print(f"  First 8 bytes (hex): {' '.join(f'{b:02X}' for b in read_binary[:8])}")
    print(f"  Data matches: {read_binary == binary_data}")
    
    # Cleanup
    if os.path.exists(filename + ".DBF"):
        os.remove(filename + ".DBF")
    if os.path.exists(filename + ".DBT"):
        os.remove(filename + ".DBT")
    
    print("\nDemo completed successfully!")


if __name__ == "__main__":
    # Run the demo
    demo_memo_functionality()
    
    # Run the tests
    print("\n" + "=" * 60)
    print("Running unit tests...")
    print("=" * 60)
    unittest.main()
