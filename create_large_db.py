#!/usr/bin/env python3
"""
Create a large DBF file by duplicating GAMES3.DBF multiple times.
This will create a DBF file that exceeds the 8K heap map limit for testing segmented processing.
"""

import os
import sys
import shutil
from pathlib import Path

# Add the parent directory to path so we can import dbf_module
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

try:
    import dbf_module
    import ndx_module
except ImportError as e:
    print(f"Error importing modules: {e}")
    print("Make sure you're running this from the dbase directory or that the modules are available.")
    sys.exit(1)

def copy_dbf_with_offset(source_path, target_path, record_offset):
    """Copy DBF file and modify record numbers with an offset"""
    print(f"Copying {source_path} to {target_path} with record offset {record_offset}")
    
    # Copy the file first
    shutil.copy2(source_path, target_path)
    
    # Open the copied DBF and modify record numbers
    try:
        dbf = dbf_module.dbf_file_open(target_path)
        if not dbf:
            print(f"Failed to open {target_path}")
            return False
            
        original_count = dbf_module.dbf_file_get_actual_row_count(dbf)
        print(f"Original records: {original_count}")
        
        # Update each record to add offset to year field
        for rec_no in range(original_count):
            dbf_module.dbf_file_seek_to_row(dbf, rec_no)
            row = dbf_module.dbf_file_read_row(dbf)
            
            # Get the original year and add offset
            year_str = dbf_module.dbf_file_get_field_str(row, dbf, 2)  # YEAR field
            try:
                year = int(year_str)
                new_year = year + record_offset
                
                # Update the year field
                dbf_module.dbf_file_set_field_str(row, dbf, 2, str(new_year))
                dbf_module.dbf_file_write_row(dbf, rec_no, row)
            except ValueError:
                # Skip if year is not a valid number
                pass
        
        dbf_module.dbf_file_close(dbf)
        return True
        
    except Exception as e:
        print(f"Error modifying DBF: {e}")
        return False

def create_large_dbf():
    """Create a large DBF file by duplicating GAMES3.DBF multiple times"""
    
    # Paths
    samples_dir = Path("samples")
    source_dbf = samples_dir / "GAMES3.DBF"
    target_dbf = samples_dir / "LARGEDB.DBF"
    
    if not source_dbf.exists():
        print(f"Source file {source_dbf} not found!")
        return False
    
    print("Creating large DBF file for segmented heap map testing...")
    print("=" * 60)
    
    # First, get the original record count
    try:
        dbf = dbf_module.dbf_file_open(str(source_dbf))
        if not dbf:
            print("Failed to open source DBF")
            return False
            
        original_count = dbf_module.dbf_file_get_actual_row_count(dbf)
        dbf_module.dbf_file_close(dbf)
        
        print(f"Source: {source_dbf}")
        print(f"Original records: {original_count}")
        print(f"8K heap map limit: 8192 records")
        
    except Exception as e:
        print(f"Error reading source DBF: {e}")
        return False
    
    # Calculate how many copies we need to exceed 8K
    copies_needed = (8192 // original_count) + 2  # 2 extra to be sure we exceed 8K
    target_records = original_count * copies_needed
    
    print(f"Will create {copies_needed} copies for total of {target_records} records")
    print(f"This exceeds 8K limit by {target_records - 8192} records")
    print()
    
    # Correct approach: write one header, then append only record bytes for each copy
    print("Creating large DBF by appending records (no duplicate headers)...")
    
    try:
        # Read the original file header and record layout
        with open(source_dbf, 'rb') as f:
            header = f.read(32)
            if len(header) < 32:
                print("Source DBF header is too short")
                return False
            # DBF header: record count at bytes 4-7, header size at 8-9, record size at 10-11
            original_count = int.from_bytes(header[4:8], byteorder='little', signed=False)
            header_size = int.from_bytes(header[8:10], byteorder='little', signed=False)
            record_size = int.from_bytes(header[10:12], byteorder='little', signed=False)
            if header_size == 0 or record_size == 0:
                print("Invalid header or record size in source DBF")
                return False
            f.seek(0)
            header_block = f.read(header_size)
            if len(header_block) < header_size:
                print("Failed to read full DBF header")
                return False
            # Read only the record bytes (exclude any terminator)
            record_bytes_len = original_count * record_size
            f.seek(header_size)
            record_data = f.read(record_bytes_len)
            if len(record_data) < record_bytes_len:
                print("Source DBF appears truncated (not enough record data)")
                return False
        
        # Write the new DBF: header once, then record data repeated
        with open(target_dbf, 'wb') as f:
            f.write(header_block)
            for i in range(copies_needed):
                f.write(record_data)
                print(f"Added record batch {i+1}/{copies_needed}")
            # DBF EOF marker
            f.write(b'\x1A')
        
        print(f"\nSuccessfully created {target_dbf}")
        print(f"File size: {os.path.getsize(target_dbf)} bytes")
        
        # Verify the created file and update record count
        try:
            # Update the record count in the DBF header
            with open(target_dbf, 'r+b') as f:
                # Read the header
                header_data = bytearray(32)
                f.readinto(header_data)
                
                # Update record count (bytes 4-7, little-endian)
                import struct
                new_count = target_records
                header_data[4:8] = struct.pack('<I', new_count)
                
                # Write back the updated header
                f.seek(0)
                f.write(header_data)
            
            # Now verify with DBF module
            dbf = dbf_module.dbf_file_open(str(target_dbf))
            if dbf:
                actual_count = dbf_module.dbf_file_get_actual_row_count(dbf)
                dbf_module.dbf_file_close(dbf)
                print(f"Verification: {target_dbf} has {actual_count} records")
                
                if actual_count >= 8000:
                    print("✓ This file will trigger the 8K heap map limit!")
                else:
                    print("ℹ This file is close to the 8K limit")
                
                return True
            else:
                print("Failed to verify created file")
                return False
                
        except Exception as e:
            print(f"Error verifying created file: {e}")
            return False
            
    except Exception as e:
        print(f"Error during file creation: {e}")
        return False

def create_index():
    """Create an NDX index on the DEVNAME field for testing"""
    
    target_dbf = "samples/LARGEDB.DBF"
    target_ndx = "samples/LARGEDB.NDX"
    
    if not os.path.exists(target_dbf):
        print(f"DBF file {target_dbf} not found. Create it first.")
        return False
    
    print(f"\nCreating NDX index on DEVNAME field...")
    print("DEVNAME has many duplicates, making it ideal for efficient NDX indexing")
    print("This demonstrates how NDX compression works with duplicate values")
    
    try:
        # Create index on DEVNAME field (need to find the field index)
        dbf = dbf_module.dbf_file_open(target_dbf)
        if not dbf:
            print(f"Failed to open {target_dbf}")
            return False
        
        # Find the DEVNAME field index
        devname_field_idx = -1
        header = dbf_module.read_dbf_header(open(target_dbf, 'rb'))
        for i in range(1, header.field_count + 1):
            field_name = header.fields[i].name
            # Handle both string and bytes field names
            if isinstance(field_name, bytes):
                field_name_str = field_name.decode('ascii', errors='ignore').strip('\x00')
            else:
                field_name_str = str(field_name).strip()
            
            if field_name_str.upper() == 'DEVNAME':
                devname_field_idx = i
                break
        
        dbf_module.dbf_file_close(dbf)
        
        if devname_field_idx == -1:
            print("DEVNAME field not found in DBF")
            return False
        
        print(f"Found DEVNAME field at index {devname_field_idx}")
        
        # Create index on DEVNAME field
        success = ndx_module.ndx_create_index(target_dbf, "DEVNAME", target_ndx)
        
        if success and os.path.exists(target_ndx):
            print(f"✓ Successfully created {target_ndx}")
            print("This index demonstrates efficient NDX compression with duplicate values")
            print("Combined with heap map numeric filtering, this shows optimal performance:")
            print("1. NDX: Fast pre-filtering by developer (many duplicates = efficient)")
            print("2. Heap Map: Numeric filtering on reduced result set")
            print("3. Segmentation: Handle large datasets exceeding memory limits")
            return True
        else:
            print(f"✗ Failed to create {target_ndx}")
            return False
            
    except Exception as e:
        print(f"Error creating NDX index: {e}")
        return False

def main():
    """Main function"""
    print("Large DBF Creator for Segmented Heap Map Testing")
    print("=" * 60)
    
    # Create the large DBF file
    if create_large_dbf():
        print("\n✓ Large DBF creation completed successfully!")
        
        # Create the index
        if create_index():
            print("\n✓ Index creation completed successfully!")
            print("\nFiles created:")
            print("  - samples/LARGEDB.DBF (large dataset for testing)")
            print("  - samples/LARGEDB.NDX (index on YEAR field)")
            print("\nYou can now use these files to test segmented heap map processing")
            print("and verify that the 8K memory barrier is properly handled.")
        else:
            print("\n⚠ Index creation failed, but DBF file was created")
            print("You can still test the heap map functionality without the index.")
    else:
        print("\n✗ Large DBF creation failed")
        return 1
    
    return 0

if __name__ == "__main__":
    sys.exit(main())
