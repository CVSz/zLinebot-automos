from openai import OpenAI

client = OpenAI()


def run_agent(input_text: str) -> list[str]:
    tasks: list[str] = []

    if "email" in input_text.lower():
        tasks.append("email")
    if "report" in input_text.lower():
        tasks.append("report")

    results: list[str] = []
    for task in tasks:
        if task == "email":
            results.append("Email sent")
        elif task == "report":
            results.append("Report generated")

    return results
