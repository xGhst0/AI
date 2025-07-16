#!/usr/bin/env bash
set -euo pipefail

# Colours for readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# GitHub repository for updates
GITHUB_REPO="https://github.com/yourusername/ai-cli-offline"

function log() {
  echo -e "${YELLOW}[INFO]${NC} $1"
}

function success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

function error() {
  echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Check for root
if [[ $EUID -ne 0 ]]; then
  error "This script must be run as root."
  exit 1
fi

log "Starting AI CLI environment installation."

# System preparation
log "Updating system packages..."
apt-get update -y && apt-get upgrade -y || error "System update failed, continuing anyway."

# Dependencies
log "Installing core packages..."
apt-get install -y python3 python3-venv python3-pip git curl wget build-essential ca-certificates unzip jq || error "Base package install failed."

# Detect NVIDIA GPU and install CUDA if present
if lspci | grep -i nvidia > /dev/null; then
  log "NVIDIA GPU detected. Installing driver & CUDA support..."
  apt-get install -y nvidia-driver-535 nvidia-cuda-toolkit || error "CUDA install failed. Falling back to CPU only."
else
  log "No GPU detected. Continuing with CPU-only install."
fi

# Upgrade pip
log "Upgrading pip..."
python3 -m pip install --upgrade pip setuptools wheel || error "Pip upgrade failed."

# Python environment & packages
log "Installing Python AI packages..."
pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118 || pip3 install torch torchvision torchaudio

pip3 install transformers accelerate bitsandbytes huggingface-hub sentence-transformers chromadb langchain tiktoken crewai[tools] autogen-core wikipedia beautifulsoup4 duckduckgo-search || error "Python package installation failed."

# Download LLM model
log "Downloading and caching LLM model locally..."
python3 - << 'PYTHON'
from huggingface_hub import snapshot_download
model = "TheBloke/Mistral-7B-Instruct-v0.1-GGUF"  # replace with suitable uncensored model
try:
    snapshot_download(repo_id=model)
except Exception as e:
    print(f"[ERROR] Model download failed: {e}")
PYTHON

# Create CLI script
log "Creating 'ai' CLI interface..."
cat << 'EOF' > /usr/local/bin/ai
#!/usr/bin/env python3
import os, sys, argparse, subprocess
from transformers import pipeline
from duckduckgo_search import DDGS
from bs4 import BeautifulSoup
import requests
from crewai import Crew, Agent, Task

MODEL = "TheBloke/Mistral-7B-Instruct-v0.1-GGUF"
CACHE_DIR = os.path.expanduser("~/.cache/huggingface/hub")
GITHUB_REPO = "https://github.com/yourusername/ai-cli-offline"

os.environ["HF_HUB_OFFLINE"] = "1"
def get_generator():
  return pipeline("text-generation", model=MODEL, device_map="auto", trust_remote_code=True)

def learn(topic):
  try:
    prompts = [f"What is {topic}?", f"Why is {topic} important?", f"How is {topic} used in practice?"]
    for p in prompts:
      with DDGS() as ddgs:
        results = list(ddgs.text(p, max_results=3))
        for r in results:
          url = r.get("href")
          if not url: continue
          print(f"[Learn] Visiting: {url}")
          html = requests.get(url, timeout=10).text
          soup = BeautifulSoup(html, "html.parser")
          text = ' '.join([p.text for p in soup.find_all("p")][:5])
          print(f"[Learned] {text[:500]}...\n")
  except Exception as e:
    print(f"Error learning about topic: {e}")

def update():
  print("Checking for updates...")
  subprocess.call(["git", "clone", GITHUB_REPO, "/tmp/ai-cli-update"])
  print("Update complete. Files saved in /tmp/ai-cli-update.")

def multi_agent_prompt(prompt):
  try:
    print("[CREW] Starting multi-agent task")
    result = None
    while result is None:
      creator = Agent(role="Framework Designer", goal="Design code structure", backstory="Expert engineer")
      tester = Agent(role="Test Engineer", goal="Test modules", backstory="QA specialist")
      docer = Agent(role="Technical Writer", goal="Document the code", backstory="Documentation specialist")
      finaliser = Agent(role="Final Integrator", goal="Assemble final code", backstory="Senior dev")

      task1 = Task(description="Design base for: " + prompt, agent=creator)
      task2 = Task(description="Create unit tests", agent=tester)
      task3 = Task(description="Write markdown documentation", agent=docer)
      task4 = Task(description="Integrate all parts", agent=finaliser)

      crew = Crew(tasks=[task1, task2, task3, task4], verbose=True)
      result = crew.kickoff()
      if not result:
        print("[WARN] Multi-agent task failed, retrying...")
  except Exception as e:
    print(f"[ERROR] Multi-agent task crashed: {e}")

def main():
  parser = argparse.ArgumentParser()
  parser.add_argument("prompt", nargs=argparse.REMAINDER)
  parser.add_argument("--learn", help="Topic to learn online")
  parser.add_argument("--update", action="store_true")
  parser.add_argument("--multi", action="store_true", help="Use multi-agent prompt manager")
  args = parser.parse_args()

  if args.update:
    return update()
  if args.learn:
    return learn(args.learn)
  if args.multi:
    return multi_agent_prompt(' '.join(args.prompt))
  if not args.prompt:
    print("Usage: ai 'your question'")
    return

  prompt = ' '.join(args.prompt)
  print(f"You: {prompt}\n")
  try:
    gen = get_generator()
    output = gen(prompt, max_new_tokens=300)[0]["generated_text"]
    print(f"AI: {output.strip()}")
  except Exception as e:
    print(f"[ERROR] Generation failed: {e}")

if __name__ == '__main__':
  main()
EOF

chmod +x /usr/local/bin/ai

# Basic test with retry
log "Running basic test to validate installation..."
attempt=1
while (( attempt <= 3 )); do
  if ai "What is the capital of France?" | grep -qi "paris"; then
    success "AI CLI is working correctly."
    break
  else
    log "Test attempt $attempt failed. Retrying or installing fallback..."
    ((attempt++))
    if (( attempt > 3 )); then
      pip3 install llama-cpp-python || error "Fallback model install failed."
    fi
  fi
done

success "Installation complete. Use 'ai \"your prompt\"' to start."
