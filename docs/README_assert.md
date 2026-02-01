# Python Assert Module

This is a Python implementation of a Pascal assertion module (ASSERT.PAS). The module provides simple assertion utilities for testing.

## Features

- Track test runs and failures
- Named test cases
- Various assertion types:
  - `assert_true`: Assert that a condition is True
  - `assert_false`: Assert that a condition is False
  - `assert_equals_int`: Assert that two integers are equal
  - `assert_equals_str`: Assert that two strings are equal with detailed output

## Usage

```python
import assert_module as am

# Start a test
am.begin_test("My Test")

# Make assertions
am.assert_true(1 + 1 == 2, "Addition works")
am.assert_equals_int(42, 40 + 2, "Integer equality")
am.assert_equals_str("hello", "hello", "String equality")

# End the test
am.end_test()

# Print summary of all tests
am.print_summary()
```

## Running the Example

To run the example test file:

```
python test_assert_module.py
```

This will execute the test cases and display the results, including any failures and a summary of tests run.

## Differences from Pascal Version

- Uses Python naming conventions (snake_case instead of PascalCase)
- Takes advantage of Python's dynamic typing
- Maintains the same core functionality and behavior
