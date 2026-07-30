# Private & Enterprise Deployments

Ordo is designed to give organizations maximum flexibility and control. Whether you prefer simple cloud usage or a fully private, secure deployment, we offer options tailored for real-world production environments.

## Deployment Options

| Option                    | Hosting     | Management   | Best For                              | Starting Price                  |
|---------------------------|-------------|--------------|---------------------------------------|---------------------------------|
| **Pro SaaS**              | Ordo        | Ordo         | Most teams                            | $79 / month                     |
| **Managed Private**       | Ordo        | Ordo         | Security-conscious teams              | $299 – $499 / month             |
| **Self-Hosted**           | You         | You          | Full control & compliance             | $3,999 – $5,999 / year          |
| **Enterprise**            | You         | You          | Highly regulated environments         | Custom Quote                    |

---

### Pro SaaS Limits

- **500,000 API calls per month**
- Up to **10 servers**
- 30 Team Members

**Recommended Polling Intervals (if using stats polling):**
- **30–60 seconds** — Good balance for most Pro SaaS users
- **2–5 minutes** — For cost-sensitive or large fleets

### 1. Managed Private VPS

We provision and manage a **dedicated VPS instance** of Ordo exclusively for your organization.

**Key Features:**
- Dedicated resources (no multi-tenancy)
- IP whitelist firewall + DDoS protection
- Custom network rules and monitoring
- Proactive maintenance and security updates
- Priority support

**Best for:** Teams that want strong isolation and security without managing infrastructure themselves.

**Note on Polling:**  
Higher frequency polling (e.g. every 10 seconds) is fully supported here, as it does not consume shared SaaS API quota. You can also choose larger VPS sizes (more CPU, memory, and bandwidth) to comfortably support aggressive polling if needed.

### 2. Self-Hosted

Run Ordo completely on **your own infrastructure**.

**Key Features:**
- Annual commercial license
- Unlimited jobs, servers, and users
- Easy Docker-based deployment
- Regular security updates and patches

**Best for:** Organizations with strict data sovereignty or compliance requirements.

**[Full Self-Hosted Setup Guide](#docs/self-hosted)**

### 3. Enterprise

Fully customized deployments for the most demanding and regulated environments.

**Key Features:**
- On-premises or air-gapped installation support
- Custom compliance assistance
- Long-term support contracts
- Flexible support processes tailored to your security constraints

**Best for:** Finance, government, healthcare, defense, and other highly regulated industries.

---

### Want Something Else?

We’re flexible. Need a hybrid approach, specific compliance requirements, custom features, higher limits, or a completely tailored solution?

**Just ask.** We’ll work with your team to design the right deployment model for your security, scale, and operational needs.

- Email us at `ordosched@proton.me` for a personalized consultation and quote.
