# Technology Stack

## Core Platform
- **Salesforce DX:** Modern developer experience for Salesforce development, utilizing source-driven development.
- **Source API Version:** 65.0

## Frontend
- **Lightning Web Components (LWC):** Custom elements built using HTML and modern JavaScript (ES6+), adhering to Web Components standards.
- **CSS:** Standard CSS for styling, supplemented by Salesforce Lightning Design System (SLDS) design tokens where appropriate.

## Backend
- **Apex:** Strongly typed, object-oriented programming language used to execute flow and transaction control statements on the Salesforce platform.

## Testing
- **LWC Testing:** [Jest](https://jestjs.io/) for unit testing Lightning Web Components.
- **Apex Testing:** Apex Unit Testing framework for server-side logic and data access verification.

## Tooling & Quality
- **Salesforce CLI (sf/sfdx):** For environment management, deployment, and source synchronization.
- **Node.js:** Runtime for development tools.
- **ESLint:** Pluggable linting utility for JavaScript.
- **Prettier:** Opinionated code formatter with support for Apex via plugin.
- **Husky & lint-staged:** For managing Git hooks and running linters/formatters on staged files.
