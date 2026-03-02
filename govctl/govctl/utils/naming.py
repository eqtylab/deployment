"""Naming utilities for govctl."""

import random
import string


def generate_domain_code() -> str:
    """Generate a random code: 1 lowercase letter + 4 digits."""
    letter = random.choice(string.ascii_lowercase)
    digits = "".join(random.choices(string.digits, k=4))
    return f"{letter}{digits}"
