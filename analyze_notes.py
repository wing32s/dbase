#!/usr/bin/env python3
"""
MS-DOS.xml Notes Analysis Script
Analyzes Notes elements to track character sizes and calculate statistics.
"""

import xml.etree.ElementTree as ET
import sys
from collections import defaultdict

def analyze_notes(xml_file):
    """Analyze Notes elements in MS-DOS.xml and calculate statistics."""
    
    try:
        # Parse the XML file
        tree = ET.parse(xml_file)
        root = tree.getroot()
        
        # Statistics tracking
        notes_count = 0
        total_chars = 0
        max_length = 0
        max_length_note = ""
        lengths = []
        
        # Find all Notes elements
        notes_elements = root.findall('.//Notes')
        
        print(f"Found {len(notes_elements)} Notes elements")
        print("=" * 50)
        
        for i, notes in enumerate(notes_elements, 1):
            if notes.text:
                note_text = notes.text.strip()
                note_length = len(note_text)
                
                # Update statistics
                notes_count += 1
                total_chars += note_length
                lengths.append(note_length)
                
                # Track maximum
                if note_length > max_length:
                    max_length = note_length
                    max_length_note = note_text
                
                # Display progress every 100 notes
                if i % 100 == 0 or i == len(notes_elements):
                    print(f"Processed {i} notes...")
        
        # Calculate statistics
        if notes_count > 0:
            average_length = total_chars / notes_count
            
            # Find minimum
            min_length = min(lengths)
            
            # Calculate median
            sorted_lengths = sorted(lengths)
            n = len(sorted_lengths)
            if n % 2 == 0:
                median_length = (sorted_lengths[n//2 - 1] + sorted_lengths[n//2]) / 2
            else:
                median_length = sorted_lengths[n//2]
            
            # Display results
            print("\n" + "=" * 50)
            print("NOTES ANALYSIS RESULTS")
            print("=" * 50)
            print(f"Total Notes elements: {notes_count}")
            print(f"Total characters: {total_chars:,}")
            print(f"Average length: {average_length:.2f} characters")
            print(f"Median length: {median_length:.2f} characters")
            print(f"Minimum length: {min_length} characters")
            print(f"Maximum length: {max_length} characters")
            
            # Show distribution
            print("\nLength Distribution:")
            ranges = [
                (0, 50, "Very Short (0-50)"),
                (51, 100, "Short (51-100)"),
                (101, 200, "Medium (101-200)"),
                (201, 500, "Long (201-500)"),
                (501, 1000, "Very Long (501-1000)"),
                (1001, float('inf'), "Extremely Long (1000+)")
            ]
            
            for min_len, max_len, label in ranges:
                count = sum(1 for length in lengths if min_len <= length <= max_len)
                percentage = (count / notes_count) * 100
                print(f"  {label}: {count} notes ({percentage:.1f}%)")
            
            # Show longest note
            print(f"\nLongest Note ({max_length} characters):")
            print("-" * 30)
            # Truncate if too long for display
            if len(max_length_note) > 200:
                print(max_length_note[:200] + "...")
            else:
                print(max_length_note)
            print("-" * 30)
            
        else:
            print("No Notes elements found with text content.")
            
    except FileNotFoundError:
        print(f"Error: File '{xml_file}' not found.")
        sys.exit(1)
    except ET.ParseError as e:
        print(f"Error parsing XML file: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"Unexpected error: {e}")
        sys.exit(1)

def main():
    """Main function."""
    xml_file = "samples/MS-DOS.xml"
    
    print("MS-DOS.xml Notes Analysis")
    print("=" * 50)
    print(f"Analyzing: {xml_file}")
    print()
    
    analyze_notes(xml_file)

if __name__ == "__main__":
    main()
