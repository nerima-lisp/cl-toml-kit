# Data model

TOML scalars use explicit value objects. Integers, floats, booleans, empty
collections, and missing keys are distinct. Tables preserve insertion order.
Date and time values use the corresponding `cl-date-kit` objects directly.
