import os
from strands import Agent, tool
from strands.models import BedrockModel
from strands_tools import use_aws, retrieve, http_request
from strands.session.file_session_manager import FileSessionManager
from dotenv import load_dotenv

load_dotenv(dotenv_path=".env")
GUARDRAIL_ID = os.getenv("GUARDRAIL_ID")
GUARDRAIL_VERSION = os.getenv("GUARDRAIL_VERSION")
KNOWLEDGE_BASE_ID = os.getenv("KNOWLEDGE_BASE_ID")
MODEL_ID = os.getenv("MODEL_ID")
REGION = os.getenv("REGION")


def my_agent():

  
    bedrock_model = BedrockModel(
        model_id=MODEL_ID,
        region_name=REGION,
        temperature=0.3,
        max_tokens=2000,
        #guardrail_id=GUARDRAIL_ID,
        #guardrail_version=GUARDRAIL_VERSION,
        context_window_limit=100000,
       
    )

    system_prompt = f"""
    You are my personal assistant.
    
    IMPORTANT:
    - You have access to past conversation history via session memory.
    - Always use prior messages in the session if relevant.
    - If user asks about previous conversation, answer using session memory.



    You have two jobs:

    1. AWS account assistant:
    Use the use_aws tool for AWS account queries.
    Default region is {REGION}.

    2. University knowledge base assistant:
    If the user asks about university, courses, admissions, academic calendar,
    housing, hostels, dining, mess, registration, campus, or fees,
    always use the retrieve tool first.

    When using retrieve, use:
    - knowledgeBaseId: {KNOWLEDGE_BASE_ID}
    - region: {REGION}
    - numberOfResults: 5
    - enableMetadata: true

    If retrieve returns relevant results:
    - Answer from the retrieved content.
    - Include citations/sources if available.

    If retrieve returns no relevant result:
    - Say clearly that the answer was not found in the knowledge base.
    - Then optionally provide a general answer.

    Do not invent Greenfield University details.
    Do not include <thinking> tags in the final answer.

    3. Web Crawler Assitant
    If the user asks about a specific website information, call the website using http and find relevant information


    """

    session_manager = FileSessionManager(
        session_id = "user3-session",
        storage_dir = "./sessions"
    )

    agent = Agent(
        model=bedrock_model,
        tools=[use_aws, retrieve, http_request],
        system_prompt=system_prompt,
        context_manager = "auto",
        session_manager = session_manager
    )

    return agent

def main():
    print("I am your personal  Assistant. Ask me anything about your AWS account or Greenfield university or any website")
  

    agent = my_agent()

    while True:
        user_input = input("You: ").strip()

        if not user_input:
            continue
        if user_input.lower() in ("quit", "exit", "q"):
            print("GoodBye")
            break

        print("\nAssistant: ", end="", flush=True)
        response = agent(user_input)
        print(f"\n{response}\n")

if __name__ == "__main__":
    main()