import os
from strands import Agent, tool
from strands.models import BedrockModel
from strands_tools import retrieve
import os
from dotenv import load_dotenv

load_dotenv(dotenv_path=".env")  # Load environment variables from .env file

# ============================================================
# Configuration — Replace these with your resource IDs
# ============================================================


GUARDRAIL_ID = os.getenv("GUARDRAIL_ID")
GUARDRAIL_VERSION = os.getenv("GUARDRAIL_VERSION")
KNOWLEDGE_BASE_ID = os.getenv("KNOWLEDGE_BASE_ID")
MODEL_ID = os.getenv("MODEL_ID")
REGION = os.getenv("REGION")


# ============================================================
# Custom Tool: Look Up Course Schedule
# ============================================================

import os
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry
from strands import tool

# Shared session with retries — reuse across all tools
_session = requests.Session()
_session.mount(
    "https://",
    HTTPAdapter(max_retries=Retry(
        total=3, backoff_factor=0.5,
        status_forcelist=(429, 500, 502, 503, 504),
        allowed_methods=("GET",),
    )),
)
_TIMEOUT = 8


# ---------------------------------------------------------------
# 1. Weather — Open-Meteo (no auth, ~10k req/day non-commercial)
# ---------------------------------------------------------------
@tool
def get_weather(city: str) -> str:
    """Get current weather for any city worldwide.

    Args:
        city: City name, e.g., "Pune", "Tokyo", "New York".
    """
    try:
        # Step 1: geocode city -> lat/lon
        g = _session.get(
            "https://geocoding-api.open-meteo.com/v1/search",
            params={"name": city, "count": 1},
            timeout=_TIMEOUT,
        ).json()
        if not g.get("results"):
            return f"ERROR: City '{city}' not found."
        loc = g["results"][0]
        lat, lon, label = loc["latitude"], loc["longitude"], loc["name"]

        # Step 2: fetch current weather
        w = _session.get(
            "https://api.open-meteo.com/v1/forecast",
            params={
                "latitude": lat, "longitude": lon,
                "current": "temperature_2m,apparent_temperature,"
                           "relative_humidity_2m,wind_speed_10m,weather_code",
                "timezone": "auto",
            },
            timeout=_TIMEOUT,
        ).json()
        c = w["current"]
        return (
            f"Weather in {label} ({loc.get('country','')}):\n"
            f"- Temperature: {c['temperature_2m']}°C (feels like {c['apparent_temperature']}°C)\n"
            f"- Humidity: {c['relative_humidity_2m']}%\n"
            f"- Wind: {c['wind_speed_10m']} km/h\n"
            f"- WMO weather code: {c['weather_code']}"
        )
    except requests.RequestException as e:
        return f"ERROR: Weather service unavailable ({type(e).__name__})."


# ---------------------------------------------------------------
# 2. Crypto price — CoinGecko Demo (no key, 30 req/min)
# ---------------------------------------------------------------
@tool
def get_crypto_price(coin_id: str, vs_currency: str = "usd") -> str:
    """Get the current price of a cryptocurrency.

    Args:
        coin_id: CoinGecko coin id, e.g., "bitcoin", "ethereum", "solana".
        vs_currency: Fiat currency code, e.g., "usd", "inr", "eur".
    """
    try:
        r = _session.get(
            "https://api.coingecko.com/api/v3/simple/price",
            params={
                "ids": coin_id.lower(),
                "vs_currencies": vs_currency.lower(),
                "include_24hr_change": "true",
            },
            timeout=_TIMEOUT,
        )
        r.raise_for_status()
        data = r.json().get(coin_id.lower())
        if not data:
            return f"ERROR: Unknown coin id '{coin_id}'. Try 'bitcoin', 'ethereum', etc."
        price = data[vs_currency.lower()]
        change = data.get(f"{vs_currency.lower()}_24h_change", 0)
        return f"{coin_id.title()} = {price:,.2f} {vs_currency.upper()} (24h: {change:+.2f}%)"
    except requests.RequestException as e:
        return f"ERROR: CoinGecko unavailable ({type(e).__name__})."


# ---------------------------------------------------------------
# 3. Stocks — Alpha Vantage (free key, 25 req/day)
# ---------------------------------------------------------------
@tool
def get_stock_quote(symbol: str) -> str:
    """Get the latest daily close for a US stock.

    Args:
        symbol: Ticker symbol, e.g., "AAPL", "MSFT", "TSLA".
    """
    key = os.getenv("ALPHA_VANTAGE_KEY")
    if not key:
        return "ERROR: ALPHA_VANTAGE_KEY not configured."
    try:
        r = _session.get(
            "https://www.alphavantage.co/query",
            params={
                "function": "GLOBAL_QUOTE",
                "symbol": symbol.upper(),
                "apikey": key,
            },
            timeout=_TIMEOUT,
        ).json()
        q = r.get("Global Quote", {})
        if not q or not q.get("05. price"):
            return f"ERROR: No quote for '{symbol}' (rate limit or bad symbol)."
        return (
            f"{symbol.upper()} = ${float(q['05. price']):.2f} "
            f"({q['10. change percent']}) as of {q['07. latest trading day']}"
        )
    except requests.RequestException as e:
        return f"ERROR: Alpha Vantage unavailable ({type(e).__name__})."


# ---------------------------------------------------------------
# 4. Public holidays — Nager.Date (no auth)
# ---------------------------------------------------------------
@tool
def get_public_holidays(year: int, country_code: str) -> str:
    """Get public holidays for a country and year.

    Args:
        year: 4-digit year, e.g., 2026.
        country_code: ISO 3166-1 alpha-2 code, e.g., "US", "IN", "GB".
    """
    try:
        r = _session.get(
            f"https://date.nager.at/api/v3/PublicHolidays/{year}/{country_code.upper()}",
            timeout=_TIMEOUT,
        )
        r.raise_for_status()
        holidays = r.json()
        if not holidays:
            return f"No holidays found for {country_code} in {year}."
        lines = [f"- {h['date']}: {h['localName']} ({h['name']})" for h in holidays[:15]]
        return f"Public holidays in {country_code.upper()} {year}:\n" + "\n".join(lines)
    except requests.RequestException as e:
        return f"ERROR: Nager.Date unavailable ({type(e).__name__})."


# ---------------------------------------------------------------
# 5. Wikipedia summary — no auth
# ---------------------------------------------------------------
@tool
def wiki_summary(topic: str) -> str:
    """Get a short Wikipedia summary for a topic.

    Args:
        topic: Article title, e.g., "Albert Einstein", "Kubernetes".
    """
    try:
        title = topic.strip().replace(" ", "_")
        r = _session.get(
            f"https://en.wikipedia.org/api/rest_v1/page/summary/{title}",
            headers={"User-Agent": "StrandsDemoAgent/1.0"},
            timeout=_TIMEOUT,
        )
        if r.status_code == 404:
            return f"No Wikipedia article found for '{topic}'."
        r.raise_for_status()
        d = r.json()
        return f"{d.get('title')}: {d.get('extract')}\nURL: {d.get('content_urls',{}).get('desktop',{}).get('page','')}"
    except requests.RequestException as e:
        return f"ERROR: Wikipedia unavailable ({type(e).__name__})."
# ============================================================
# Build the Agent
# ============================================================

def create_agent():
    """Create the chatbot agent."""

    # The built-in retrieve tool reads this env var to find the KB
    os.environ["KNOWLEDGE_BASE_ID"] = KNOWLEDGE_BASE_ID
    os.environ["AWS_REGION"] = REGION

    bedrock_model = BedrockModel(
        model_id=MODEL_ID,
        region_name=REGION,
        temperature=0.3,
        max_tokens=2000,
        guardrail_id=GUARDRAIL_ID,
        guardrail_version=GUARDRAIL_VERSION
    )

    agent = Agent(
    model=bedrock_model,
    tools=[retrieve, get_weather, get_crypto_price,
           get_stock_quote, get_public_holidays, wiki_summary],
    system_prompt="""You are a helpful assistant with access to live data tools.
        - Use `get_weather` for any weather question.
        - Use `get_crypto_price` for cryptocurrency prices.
        - Use `get_stock_quote` for US stock prices (limited to 25/day).
        - Use `get_public_holidays` for national holidays by country and year.
        - Use `wiki_summary` for general knowledge lookups.
        - Use `retrieve` for anything in our internal knowledge base.
        - If a tool returns a string starting with 'ERROR:', tell the user politely
        that the live data is unavailable; do not invent values.
        """
)

    return agent


# ============================================================
# Run the Agent
# ============================================================

def main():
    print("Chatbot")
    print("=" * 60)
    print("Ask me about weather, crypto price, get stock quote, get public holidays, wikipedia summary")
    print("\nType 'quit' to exit.\n")

    agent = create_agent()

    while True:
        user_input = input("You: ").strip()
        if not user_input:
            continue
        if user_input.lower() in ("quit", "exit", "q"):
            print("Goodbye!")
            break

        print("\nAssistant: ", end="", flush=True)
        response = agent(user_input)
        print(f"\n{response}\n")


if __name__ == "__main__":
    main()
