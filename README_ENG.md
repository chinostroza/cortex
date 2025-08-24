<div align="center">
  <img src="logo.png" alt="Córtex Logo" width="200"/>
</div>

# 🧠 Córtex

**Your own brain to orchestrate multiple AI models at minimal cost.**

Córtex is an intelligent inference gateway and load balancer built on **Elixir** and **Phoenix**. Its mission is to empower developers to build robust, scalable AI applications on a near-zero budget by offering a dual-license model that supports both the open-source community and commercial needs.

---

## 🤔 Why Does Córtex Exist?

AI APIs are amazing, but they can cost an arm and a leg 💸! Córtex solves this problem by creating a central "brain" that intelligently manages your AI resources, always prioritizing free or self-hosted options first. Build without fear of the bill!

---

## ✨ Key Features

* **Hybrid Architecture 🏡+☁️:** Prioritizes local workers and only uses cloud APIs as a backup.
* **Automatic Failover 🛡️:** If a local server takes a break (goes down), Córtex automatically reroutes traffic. The show must go on!
* **API Key Rotation 🔑:** Manages a pool of multiple free API keys to squeeze every last drop out of their rate limits.
* **GOD-Tier Fault Tolerance 💪:** Built on Elixir/OTP, a crash in one worker won't even make the rest of the system blink.
* **Magic Cache 🧠 (Roadmap):** Will soon use ETS to store common answers for lightning-fast, instant responses.
* **Intelligent Routing 🗺️ (Roadmap):** Future ability to route prompts to the best-suited model for the task.
* **Monitoring Dashboard (Roadmap):** A real-time dashboard with Phoenix LiveView to watch our workers in action.

---

## 📮 How Does It Work? The Magical Post Office!

Imagine Córtex is a magical post office for your AI requests:

1.  **The Receptionist (`Router`) 🧑‍💼:** Receives your letter (`POST /api/chat`) and, without reading it, places it in the Manager's inbox.
2.  **The Office Manager (`Controller`) 👨‍💼:** Opens the letter, prepares the connection to send the reply in pieces (streaming!), and gives the order to the Courier.
3.  **The Magical Courier (`Dispatcher`) 🚀:** Takes the order, travels at lightning speed ⚡ to the Oracle (`Ollama`), delivers your question, and returns with the answer.
4.  **The Manager, again 👨‍💼:** Receives the answer from the courier and sends it out the window to the client, piece by piece.

---

## 🛠️ Installation & Getting Started

Let's get our hands dirty! To get Córtex running on your machine.

#### **Prerequisites**

Make sure you have:
* [Elixir](https://elixir-lang.org/install.html) installed.
* [Ollama](https://ollama.com/) installed and running.
* Git to clone the project.

#### **Steps**

1.  **Clone the Repository:**
    ```bash
    git clone [https://github.com/your-username/cortex.git](https://github.com/your-username/cortex.git)
    cd cortex
    ```

2.  **Install Elixir Dependencies:**
    ```bash
    mix deps.get
    ```

3.  **Configure Your Servers:**
    * Create your personal config file by copying the example:
        ```bash
        cp .env.example .env
        ```
    * Open the `.env` file and edit it with your worker URLs and API keys (more info below).

4.  **Launch! 🚀**
    * **In one terminal**, start your AI server:
        ```bash
        ollama serve
        ```
    * **In another terminal**, start Córtex:
        ```bash
        mix phx.server
        ```

Done! Your Córtex gateway is now listening at `http://localhost:4000`.

---

## ⚙️ Configuration

All Córtex configuration is handled in the `.env` file.

* `ROUTING_STRATEGY`: How workers are selected. For now, `local_first`.
* `LOCAL_OLLAMA_URLS`: A comma-separated list of your local Ollama server URLs.
* `GEMINI_API_KEYS`: Your comma-separated Google Gemini API keys.
* `COHERE_API_KEYS`: Your comma-separated Cohere API keys.
* ...and more workers to be added in the future!

---

## 🎮 Usage

To test that everything is working, send a `POST` request to the API with `curl`. The `-N` flag is to see the streaming in real-time.

```bash
curl -N -X POST http://localhost:4000/api/chat \
-H "Content-Type: application/json" \
-d '{
  "messages": [
    {
      "role": "user",
      "content": "Write a short poem about Elixir and concurrency."
    }
  ]
}'
````

You should see the poem's response being typed out word by word in your terminal. Magic\! ✨

-----

## 🗺️ Roadmap (Our Next Spells)

  * [ ] 🧠 **Intelligent Cache:** Implement caching with ETS for instant responses.
  * [ ] 🗺️ **Task-Based Routing:** Teach the Dispatcher to choose the best model for each type of question.
  * [ ] 📊 **Monitoring Dashboard:** A LiveView dashboard to see our workers in action in real-time.
  * [ ] 🔌 **More Workers:** Add native support for more AI APIs.

-----

## 🤝 Want to Contribute? Join the Magic\!

Contributions are welcome\! If you have an idea or want to fix a bug:

1.  Open an "Issue" to discuss your idea.
2.  "Fork" the repository.
3.  Create a new branch (`git checkout -b my-new-feature`).
4.  Make your changes and submit a "Pull Request".

-----

## 📜 License

Córtex is distributed under the **GNU Affero General Public License v3.0 (AGPLv3)**. This means you are free to use, modify, and distribute it. If you use it to power a service available over a network, the license requires that the full source code of your service must also be made public.

You can read the full license [here](https://www.gnu.org/licenses/agpl-3.0.html).

-----

## 💼 Commercial License

If the terms of the AGPLv3 are not compatible with your business model (for example, if you wish to offer Córtex as a closed-source service), a commercial license is available.

For more details, please contact **Carlos Hinostroza** at **c@zea.cl**.