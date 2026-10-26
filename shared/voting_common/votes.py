"""Vote choices shared by the frontend and the worker."""

VOTE_CHOICES = {
    "cats": {
        "label": "Cats",
        "tagline": "Soft. Scheming. Superior.",
    },
    "dogs": {
        "label": "Dogs",
        "tagline": "Loyal. Loud. Undefeated.",
    },
}

VALID_CHOICES = frozenset(VOTE_CHOICES)
