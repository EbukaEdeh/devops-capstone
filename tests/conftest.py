import os

# Keep module import side-effect free for unit tests. Gunicorn imports the
# module in the normal runtime where this flag is unset.
os.environ.setdefault("VOTING_TEST_MODE", "1")
