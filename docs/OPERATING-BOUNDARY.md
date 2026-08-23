# Operating boundary

Route Steward manages self-hosted network paths on infrastructure selected and controlled by the operator. This document defines the conditions that make that operating model clear and reproducible.

## Authorized infrastructure

The operator supplies the servers, accounts, SSH access, client devices, network connectivity, and any external configuration-delivery account used by a deployment. Each resource is owned by the operator or administered with the resource owner's authorization.

## Internet and provider context

Route Steward assumes Internet reachability between the endpoints selected for a Route. Carriers, cloud providers, hosting providers, and organizational networks remain the source of that connectivity and retain the visibility and policy role inherent to their service.

Deployments use network products and communication services approved for their location and scenario. Regulated organizational and cross-border environments use the carrier services, approvals, records, and internal controls required for that environment.

## Operator responsibility

The operator selects the deployment topology and confirms that its purpose, infrastructure, software clients, and traffic handling align with:

- applicable laws and regulatory requirements;
- carrier and cloud-provider service terms;
- organizational security and acceptable-use policies;
- authorization from the owners of participating systems and accounts.

## Project distribution

The open-source project distributes local automation, schemas, renderers, tests, and documentation. Each Route runs in operator-selected environments under the operator's accounts. The deterministic engine records desired state locally and applies scoped changes after preflight establishes the target, expected effects, access, and authorization class.

Technical capabilities are listed in [Compatibility](COMPATIBILITY.md). Infrastructure ownership and mutation boundaries are listed in [Operations](../OPERATIONS.md), [Security](../SECURITY.md), and the [Threat model](THREAT-MODEL.md).
