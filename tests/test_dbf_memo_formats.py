"""
Test file for dBase III vs dBase IV memo format differences.
This tests that the correct format is used based on DBF version.
"""

import os
import struct
import unittest
from dbf_module import (
    DBFColumn, DBFHeader, DBFFile,
    dbf_file_create, dbf_file_create_dbase3, dbf_file_close,
    dbf_memo_write, dbf_memo_write_buffer, dbf_memo_get_info,
    dbf_memo_read_small, dbf_memo_read_binary,
    DBF_MEMO_BLOCK_SIZE
)


class TestDBFMemoFormats(unittest.TestCase):
    """Test cases for dBase III vs dBase IV memo formats."""
    
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
    
    def test_dbase3_memo_format(self):
        """Test that dBase III uses simple format (no header)."""
        # Create dBase III database with memo field
        fields = [
            DBFColumn(name="NOTES", field_type="M", length=10, decimals=0)
        ]
        
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        
        filename = "test_dbase3_memo"
        dbf = dbf_file_create_dbase3(filename, header)
        
        # Verify version is 0x03
        self.assertEqual(dbf.header.version, 0x03)
        
        dbf_file_close(dbf)
        
        # Add to cleanup list
        self.test_files.append(filename + ".DBF")
        
        # Write memo data
        test_text = "Hello dBase III"
        block_num = dbf_memo_write(filename + ".DBT", 1, test_text)
        
        # Verify memo was written
        self.assertGreater(block_num, 0)
        
        # Read the raw memo block to verify format
        with open(filename + ".DBT", 'rb') as f:
            # Seek to memo block
            f.seek(block_num * DBF_MEMO_BLOCK_SIZE)
            
            # Read first 20 bytes
            raw_data = f.read(20)
            
            # For dBase III: should start with the text directly (no 8-byte header)
            # First character should be 'H' (0x48)
            self.assertEqual(raw_data[0], ord('H'))
            
            # Find the terminator
            terminator_pos = raw_data.find(b'\x1A')
            self.assertGreater(terminator_pos, 0)
            
            # Data before terminator should be our text
            data_before_terminator = raw_data[:terminator_pos]
            self.assertEqual(data_before_terminator.decode('utf-8'), test_text)
        
        # Read memo using API
        memo_type, read_text = dbf_memo_read_small(filename + ".DBT", block_num)
        self.assertEqual(memo_type, 1)
        self.assertEqual(read_text, test_text)
    
    def test_dbase4_memo_format(self):
        """Test that dBase IV uses header format (type + length)."""
        # Create dBase IV database with memo field
        fields = [
            DBFColumn(name="NOTES", field_type="M", length=10, decimals=0)
        ]
        
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        
        filename = "test_dbase4_memo"
        dbf = dbf_file_create(filename, header)
        
        # Verify version is 0x05 (dBase V with memo)
        self.assertEqual(dbf.header.version, 0x05)
        
        dbf_file_close(dbf)
        
        # Add to cleanup list
        self.test_files.append(filename + ".DBF")
        
        # Write memo data
        test_text = "Hello dBase IV"
        block_num = dbf_memo_write(filename + ".DBT", 1, test_text)
        
        # Verify memo was written
        self.assertGreater(block_num, 0)
        
        # Read the raw memo block to verify format
        with open(filename + ".DBT", 'rb') as f:
            # Seek to memo block
            f.seek(block_num * DBF_MEMO_BLOCK_SIZE)
            
            # Read first 30 bytes (enough for header + text)
            raw_data = f.read(30)
            
            # For dBase IV+: should start with 8-byte header
            # First 4 bytes: memo type (1 for text)
            memo_type = struct.unpack("<L", raw_data[0:4])[0]
            self.assertEqual(memo_type, 1)
            
            # Next 4 bytes: length
            memo_len = struct.unpack("<L", raw_data[4:8])[0]
            self.assertEqual(memo_len, len(test_text.encode('utf-8')))
            
            # After header: the actual text
            text_start = raw_data[8:8+memo_len]
            self.assertEqual(text_start.decode('utf-8'), test_text)
        
        # Read memo using API
        memo_type, read_text = dbf_memo_read_small(filename + ".DBT", block_num)
        self.assertEqual(memo_type, 1)
        self.assertEqual(read_text, test_text)
    
    def test_dbase3_binary_memo(self):
        """Test binary data in dBase III format."""
        # Create dBase III database
        fields = [
            DBFColumn(name="DATA", field_type="M", length=10, decimals=0)
        ]
        
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        
        filename = "test_dbase3_binary"
        dbf = dbf_file_create_dbase3(filename, header)
        dbf_file_close(dbf)
        
        self.test_files.append(filename + ".DBF")
        
        # Write binary data
        binary_data = bytes([0x00, 0x01, 0x02, 0xFF, 0xFE, 0xFD])
        block_num = dbf_memo_write_buffer(filename + ".DBT", 2, binary_data)
        
        # Read back
        memo_type, read_data = dbf_memo_read_binary(filename + ".DBT", block_num)
        
        # For dBase III, memo_type is always 1 (no type header)
        self.assertEqual(memo_type, 1)
        self.assertEqual(read_data, binary_data)
    
    def test_dbase4_binary_memo(self):
        """Test binary data in dBase IV format."""
        # Create dBase IV database
        fields = [
            DBFColumn(name="DATA", field_type="M", length=10, decimals=0)
        ]
        
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        
        filename = "test_dbase4_binary"
        dbf = dbf_file_create(filename, header)
        dbf_file_close(dbf)
        
        self.test_files.append(filename + ".DBF")
        
        # Write binary data with type 2
        binary_data = bytes([0x00, 0x01, 0x02, 0xFF, 0xFE, 0xFD])
        block_num = dbf_memo_write_buffer(filename + ".DBT", 2, binary_data)
        
        # Read back
        memo_type, read_data = dbf_memo_read_binary(filename + ".DBT", block_num)
        
        # For dBase IV+, memo_type should be preserved
        self.assertEqual(memo_type, 2)
        self.assertEqual(read_data, binary_data)
    
    def test_dbase3_memo_with_embedded_nulls(self):
        """Test dBase III memo with embedded null bytes."""
        # Create dBase III database
        fields = [
            DBFColumn(name="DATA", field_type="M", length=10, decimals=0)
        ]
        
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        
        filename = "test_dbase3_nulls"
        dbf = dbf_file_create_dbase3(filename, header)
        dbf_file_close(dbf)
        
        self.test_files.append(filename + ".DBF")
        
        # Write data with embedded nulls (but not 0x1A which is terminator)
        binary_data = b'ABC\x00\x00DEF\x00GHI'
        block_num = dbf_memo_write_buffer(filename + ".DBT", 1, binary_data)
        
        # Read back
        memo_type, read_data = dbf_memo_read_binary(filename + ".DBT", block_num)
        
        # Should preserve embedded nulls
        self.assertEqual(read_data, binary_data)
    
    def test_dbase3_empty_memo(self):
        """Test empty memo in dBase III format."""
        # Create dBase III database
        fields = [
            DBFColumn(name="NOTES", field_type="M", length=10, decimals=0)
        ]
        
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        
        filename = "test_dbase3_empty"
        dbf = dbf_file_create_dbase3(filename, header)
        dbf_file_close(dbf)
        
        self.test_files.append(filename + ".DBF")
        
        # Write empty memo
        block_num = dbf_memo_write(filename + ".DBT", 1, "")
        
        # Read back
        memo_type, read_text = dbf_memo_read_small(filename + ".DBT", block_num)
        
        self.assertEqual(memo_type, 1)
        self.assertEqual(read_text, "")
    
    def test_memo_get_info_dbase3(self):
        """Test dbf_memo_get_info with dBase III format."""
        # Create dBase III database
        fields = [
            DBFColumn(name="NOTES", field_type="M", length=10, decimals=0)
        ]
        
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        
        filename = "test_dbase3_info"
        dbf = dbf_file_create_dbase3(filename, header)
        dbf_file_close(dbf)
        
        self.test_files.append(filename + ".DBF")
        
        # Write memo
        test_text = "Test memo for info"
        block_num = dbf_memo_write(filename + ".DBT", 1, test_text)
        
        # Get info
        memo_type, memo_len = dbf_memo_get_info(filename + ".DBT", block_num)
        
        # For dBase III, type is always 1
        self.assertEqual(memo_type, 1)
        self.assertEqual(memo_len, len(test_text.encode('utf-8')))
    
    def test_memo_spans_multiple_blocks_dbase3(self):
        """Test memo spanning multiple blocks in dBase III format."""
        # Create dBase III database
        fields = [
            DBFColumn(name="NOTES", field_type="M", length=10, decimals=0)
        ]
        
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        
        filename = "test_dbase3_multiblock"
        dbf = dbf_file_create_dbase3(filename, header)
        dbf_file_close(dbf)
        
        self.test_files.append(filename + ".DBF")
        
        # Write first memo - make it large enough to span 2 blocks
        # Block size is 512 bytes, so create data > 511 bytes (need room for 0x1A)
        memo1_text = "A" * 600  # This will take 2 blocks
        block1 = dbf_memo_write(filename + ".DBT", 1, memo1_text)
        
        # Verify first memo is at block 1
        self.assertEqual(block1, 1)
        
        # Write second memo - should start at block 3 (after first memo's 2 blocks)
        memo2_text = "B" * 100
        block2 = dbf_memo_write(filename + ".DBT", 1, memo2_text)
        
        # Verify second memo skips to block 3
        self.assertEqual(block2, 3, "Second memo should start at block 3 (after 2 blocks used by first memo)")
        
        # Read both memos back and verify
        memo_type1, read_text1 = dbf_memo_read_small(filename + ".DBT", block1)
        self.assertEqual(memo_type1, 1)
        self.assertEqual(read_text1, memo1_text)
        
        memo_type2, read_text2 = dbf_memo_read_small(filename + ".DBT", block2)
        self.assertEqual(memo_type2, 1)
        self.assertEqual(read_text2, memo2_text)
    
    def test_memo_spans_multiple_blocks_dbase4(self):
        """Test memo spanning multiple blocks in dBase IV format."""
        # Create dBase IV database
        fields = [
            DBFColumn(name="NOTES", field_type="M", length=10, decimals=0)
        ]
        
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        
        filename = "test_dbase4_multiblock"
        dbf = dbf_file_create(filename, header)
        dbf_file_close(dbf)
        
        self.test_files.append(filename + ".DBF")
        
        # Write first memo - make it large enough to span 2 blocks
        # Block size is 512 bytes, with 8-byte header and 1-byte terminator
        # So data > 503 bytes will span 2 blocks
        memo1_text = "X" * 550  # This will take 2 blocks (8 + 550 + 1 = 559 bytes)
        block1 = dbf_memo_write(filename + ".DBT", 1, memo1_text)
        
        # Verify first memo is at block 1
        self.assertEqual(block1, 1)
        
        # Write second memo - should start at block 3
        memo2_text = "Y" * 100
        block2 = dbf_memo_write(filename + ".DBT", 1, memo2_text)
        
        # Verify second memo skips to block 3
        self.assertEqual(block2, 3, "Second memo should start at block 3 (after 2 blocks used by first memo)")
        
        # Read both memos back and verify
        memo_type1, read_text1 = dbf_memo_read_small(filename + ".DBT", block1)
        self.assertEqual(memo_type1, 1)
        self.assertEqual(read_text1, memo1_text)
        
        memo_type2, read_text2 = dbf_memo_read_small(filename + ".DBT", block2)
        self.assertEqual(memo_type2, 1)
        self.assertEqual(read_text2, memo2_text)
    
    def test_memo_three_memos_various_sizes(self):
        """Test three memos with various sizes to verify block allocation."""
        # Create dBase IV database
        fields = [
            DBFColumn(name="NOTES", field_type="M", length=10, decimals=0)
        ]
        
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        
        filename = "test_three_memos"
        dbf = dbf_file_create(filename, header)
        dbf_file_close(dbf)
        
        self.test_files.append(filename + ".DBF")
        
        # Memo 1: Small (fits in 1 block)
        memo1_text = "Small memo"
        block1 = dbf_memo_write(filename + ".DBT", 1, memo1_text)
        self.assertEqual(block1, 1)
        
        # Memo 2: Large (spans 3 blocks)
        # 8 (header) + 1200 (data) + 1 (terminator) = 1209 bytes = 3 blocks
        memo2_text = "Z" * 1200
        block2 = dbf_memo_write(filename + ".DBT", 1, memo2_text)
        self.assertEqual(block2, 2, "Second memo should start at block 2")
        
        # Memo 3: Medium (fits in 1 block)
        memo3_text = "Medium sized memo"
        block3 = dbf_memo_write(filename + ".DBT", 1, memo3_text)
        self.assertEqual(block3, 5, "Third memo should start at block 5 (after 3 blocks used by second memo)")
        
        # Verify all memos can be read correctly
        _, read1 = dbf_memo_read_small(filename + ".DBT", block1)
        self.assertEqual(read1, memo1_text)
        
        _, read2 = dbf_memo_read_small(filename + ".DBT", block2)
        self.assertEqual(read2, memo2_text)
        
        _, read3 = dbf_memo_read_small(filename + ".DBT", block3)
        self.assertEqual(read3, memo3_text)
    
    def test_memo_binary_spans_blocks(self):
        """Test binary memo spanning multiple blocks."""
        # Create dBase IV database
        fields = [
            DBFColumn(name="DATA", field_type="M", length=10, decimals=0)
        ]
        
        header = DBFHeader()
        header.fields = fields
        header.field_count = len(fields)
        
        filename = "test_binary_multiblock"
        dbf = dbf_file_create(filename, header)
        dbf_file_close(dbf)
        
        self.test_files.append(filename + ".DBF")
        
        # Create large binary data (2 blocks worth)
        binary1 = bytes(range(256)) * 3  # 768 bytes
        block1 = dbf_memo_write_buffer(filename + ".DBT", 2, binary1)
        self.assertEqual(block1, 1)
        
        # Second binary memo
        binary2 = bytes([0xFF, 0xFE, 0xFD] * 50)  # 150 bytes
        block2 = dbf_memo_write_buffer(filename + ".DBT", 2, binary2)
        
        # Should skip to block after first memo
        # First memo: 8 + 768 + 1 = 777 bytes = 2 blocks
        self.assertEqual(block2, 3)
        
        # Verify both can be read
        _, read1 = dbf_memo_read_binary(filename + ".DBT", block1, len(binary1))
        self.assertEqual(read1, binary1)
        
        _, read2 = dbf_memo_read_binary(filename + ".DBT", block2, len(binary2))
        self.assertEqual(read2, binary2)


def demo_memo_formats():
    """Demonstrate dBase III vs dBase IV memo formats."""
    print("DBF Memo Format Comparison Demo")
    print("=" * 60)
    
    # Create dBase III database
    print("\n1. dBase III Format:")
    print("-" * 60)
    
    fields = [DBFColumn(name="NOTES", field_type="M", length=10, decimals=0)]
    header = DBFHeader()
    header.fields = fields
    header.field_count = len(fields)
    
    filename3 = "demo_dbase3"
    dbf3 = dbf_file_create_dbase3(filename3, header)
    print(f"  Created: {filename3}.DBF (version 0x{dbf3.header.version:02X})")
    dbf_file_close(dbf3)
    
    # Write memo
    text3 = "Hello dBase III"
    block3 = dbf_memo_write(filename3 + ".DBT", 1, text3)
    print(f"  Wrote memo to block {block3}")
    
    # Check raw format
    with open(filename3 + ".DBT", 'rb') as f:
        f.seek(block3 * DBF_MEMO_BLOCK_SIZE)
        raw = f.read(20)
        print(f"  First 20 bytes (hex): {' '.join(f'{b:02X}' for b in raw)}")
        print(f"  Format: Data starts immediately (no header)")
    
    # Create dBase IV database
    print("\n2. dBase IV Format:")
    print("-" * 60)
    
    filename4 = "demo_dbase4"
    dbf4 = dbf_file_create(filename4, header)
    print(f"  Created: {filename4}.DBF (version 0x{dbf4.header.version:02X})")
    dbf_file_close(dbf4)
    
    # Write memo
    text4 = "Hello dBase IV"
    block4 = dbf_memo_write(filename4 + ".DBT", 1, text4)
    print(f"  Wrote memo to block {block4}")
    
    # Check raw format
    with open(filename4 + ".DBT", 'rb') as f:
        f.seek(block4 * DBF_MEMO_BLOCK_SIZE)
        raw = f.read(20)
        print(f"  First 20 bytes (hex): {' '.join(f'{b:02X}' for b in raw)}")
        memo_type = struct.unpack("<L", raw[0:4])[0]
        memo_len = struct.unpack("<L", raw[4:8])[0]
        print(f"  Format: Type={memo_type}, Length={memo_len}, then data")
    
    # Cleanup
    for fname in [filename3, filename4]:
        if os.path.exists(fname + ".DBF"):
            os.remove(fname + ".DBF")
        if os.path.exists(fname + ".DBT"):
            os.remove(fname + ".DBT")
    
    # Demonstrate multi-block allocation
    print("\n3. Multi-Block Memo Allocation:")
    print("-" * 60)
    
    filename_multi = "demo_multiblock"
    fields = [DBFColumn(name="NOTES", field_type="M", length=10, decimals=0)]
    header = DBFHeader()
    header.fields = fields
    header.field_count = len(fields)
    
    dbf_multi = dbf_file_create(filename_multi, header)
    print(f"  Created: {filename_multi}.DBF (version 0x{dbf_multi.header.version:02X})")
    dbf_file_close(dbf_multi)
    
    # Write first memo - spans 2 blocks
    memo1 = "A" * 600  # Large enough to span 2 blocks
    block1 = dbf_memo_write(filename_multi + ".DBT", 1, memo1)
    print(f"  Memo 1: {len(memo1)} bytes -> block {block1} (spans 2 blocks)")
    
    # Write second memo - should skip to block 3
    memo2 = "B" * 100
    block2 = dbf_memo_write(filename_multi + ".DBT", 1, memo2)
    print(f"  Memo 2: {len(memo2)} bytes -> block {block2} (after memo 1)")
    
    # Write third memo - large, spans 3 blocks
    memo3 = "C" * 1200
    block3 = dbf_memo_write(filename_multi + ".DBT", 1, memo3)
    print(f"  Memo 3: {len(memo3)} bytes -> block {block3} (spans 3 blocks)")
    
    # Write fourth memo
    memo4 = "D" * 50
    block4 = dbf_memo_write(filename_multi + ".DBT", 1, memo4)
    print(f"  Memo 4: {len(memo4)} bytes -> block {block4} (after memo 3)")
    
    print(f"\n  Block allocation summary:")
    print(f"    Blocks 1-2: Memo 1 (row #1)")
    print(f"    Block 3:    Memo 2 (row #2)")
    print(f"    Blocks 4-6: Memo 3 (row #3)")
    print(f"    Block 7:    Memo 4 (row #4)")
    
    # Cleanup
    if os.path.exists(filename_multi + ".DBF"):
        os.remove(filename_multi + ".DBF")
    if os.path.exists(filename_multi + ".DBT"):
        os.remove(filename_multi + ".DBT")
    
    print("\nDemo completed successfully!")


if __name__ == "__main__":
    # Run the demo
    demo_memo_formats()
    
    # Run the tests
    print("\n" + "=" * 60)
    print("Running unit tests...")
    print("=" * 60)
    unittest.main()
