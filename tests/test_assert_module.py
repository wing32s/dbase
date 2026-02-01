"""
Example usage of the assert_module.
This file demonstrates how to use the assertion module for testing.
"""

import assert_module as am

def test_simple_assertions():
    am.begin_test("Simple Assertions")
    am.assert_true(True, "True should be true")
    am.assert_false(False, "False should be false")
    am.assert_equals_int(42, 42, "42 should equal 42")
    am.assert_equals_str("hello", "hello", "String equality works")
    am.end_test()

def test_failing_assertions():
    am.begin_test("Failing Assertions")
    am.assert_true(1 == 2, "This should fail")
    am.assert_equals_int(5, 10, "Numbers don't match")
    am.assert_equals_str("hello", "world", "Strings don't match")
    am.end_test()

def test_more_assertions():
    am.begin_test("More Assertions")
    am.assert_true(isinstance(42, int), "42 is an integer")
    am.assert_false("x" in "abc", "x is not in abc")
    am.end_test()

if __name__ == "__main__":
    am.reset_asserts()
    
    # Run the tests
    test_simple_assertions()
    test_failing_assertions()
    test_more_assertions()
    
    # Print summary
    am.print_summary()
