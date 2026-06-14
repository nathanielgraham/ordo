# Ordo Terms of Service

**Last Updated:** June 13, 2026

By using Ordo, you agree to these Terms of Service.

### 1. Service Overview
Ordo is a modern hierarchical job scheduler with real-time monitoring, dependency management, calendar-based scheduling, and optional AI integration via the MCP protocol.

### 2. "As Is" Service
Ordo is provided **"AS IS" and "AS AVAILABLE"** without any warranties, express or implied. We do not guarantee job execution, timing, or reliability.

### 3. Limitation of Liability
To the maximum extent permitted by law, Ordo and its operators shall **not be liable** for any damages (including lost profits, data loss, or business interruption) arising from the use or inability to use the service. You are solely responsible for the design, monitoring, and outcomes of your jobs.

### 4. SSH Key Access
Ordo uses SSH keys to execute jobs on your remote servers.

- A dedicated public SSH key is deployed to each server you configure.
- The corresponding private key remains on the Ordo platform and is used only to run scheduled jobs on your behalf.
- You are responsible for the security of your servers. We recommend using dedicated low-privilege service accounts and applying strict key restrictions where possible.
- Currently, key rotation is a manual process. You may remove Ordo’s public key from any server at any time.

### 5. User Content & License Grant
You retain ownership of your jobs, schedules, and data. By using Ordo, you grant us a limited, non-exclusive, royalty-free license to access, store, process, and execute your data solely as necessary to provide the service.

### 6. Acceptable Use
You agree not to use Ordo for illegal activities, to circumvent rate limits, or in any way that harms other users or systems.

### 7. Usage Limits & Billing
- All tiers have strict monthly API call limits and server limits.
- Exceeding limits may restrict functionality (except critical state updates).
- Subscriptions are billed monthly. **No refunds** for partial months or unused time.

### 8. Indemnification
You agree to indemnify and hold Ordo harmless from any claims, damages, or liabilities arising from your use of the service or violation of these terms.

### 9. Self-Hosted Deployments
Self-hosted and private deployments are governed by separate licensing terms. Contact us for details.

### 10. Termination
We may suspend or terminate access for violations of these terms or service abuse.

### 11. Governing Law
These terms are governed by the laws of the State of Minnesota, United States.

---

Questions? Contact [ordosched@proton.me](mailto:ordosched@proton.me)
