store = BedrockKnowledgeBaseStore(
    name="user-memory",
    writable=True,
    extraction=True,
    config={
        "knowledge_base_id": KB_ID,
        "data_source_type": "CUSTOM",
        "data_source_id": DATA_SOURCE_ID
    }
)

memory_manager = MemoryManager(
    stores=[store],
    add_tool_config=True
)

agent = Agent(
    model=bedrock_model,
    tools=[...],
    system_prompt=system_prompt,
    session_manager=session_manager,
    memory_manager=memory_manager
)
``