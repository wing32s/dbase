"""
Python implementation of the Pascal ASSERT.PAS module.
This module provides simple assertion utilities for testing.
"""

# Global variables to track test status
tests_run = 0
tests_failed = 0
current_test = ""
current_failed = False
in_test = False

def begin_test(test_name):
    """Start a new test with the given name."""
    global current_test, current_failed, in_test
    print(f"Starting test: {test_name}")
    current_test = test_name
    current_failed = False
    in_test = True

def end_test():
    """End the current test and update counters."""
    global tests_run, tests_failed, current_test, current_failed, in_test
    if in_test:
        tests_run += 1
        if current_failed:
            tests_failed += 1
    in_test = False
    current_test = ""
    current_failed = False

def assert_true(condition, message):
    """Assert that a condition is True."""
    global current_failed
    if not condition:
        current_failed = True
        if current_test != "":
            print(f"FAIL: {current_test}: {message}")
        else:
            print(f"FAIL: {message}")

def assert_false(condition, message):
    """Assert that a condition is False."""
    assert_true(not condition, message)

def assert_equals_int(expected, actual, message):
    """Assert that two integers are equal."""
    assert_true(expected == actual, message)

def assert_equals_str(expected, actual, message):
    """Assert that two strings are equal."""
    global current_failed
    assert_true(expected == actual, message)
    if current_failed:
        print(f"   >> EXPECTED: [{expected}]")
        print(f"   >> ACTUAL: [{actual}]")

def reset_asserts():
    """Reset all test counters and state."""
    global tests_run, tests_failed, current_test, current_failed, in_test
    tests_run = 0
    tests_failed = 0
    current_test = ""
    current_failed = False
    in_test = False

def print_summary():
    """Print a summary of all tests run."""
    print(f"Tests: {tests_run} Passed: {tests_run - tests_failed} Failed: {tests_failed}")

# Initialize the module
reset_asserts()
