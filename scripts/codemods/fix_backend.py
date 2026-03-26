import os
import re


def process_file(path):
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    # Replace print with logger
    content = re.sub(r"print\(", "logger.info(", content)

    # Warn raw SQL
    if "SELECT" in content and "%" in content:
        print(f"[SECURITY WARNING] Possible SQL injection: {path}")

    with open(path, "w", encoding="utf-8") as f:
        f.write(content)


def run():
    for root, _, files in os.walk("backend"):
        for file in files:
            if file.endswith(".py"):
                process_file(os.path.join(root, file))


if __name__ == "__main__":
    run()
