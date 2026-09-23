# AWS cost model

Prices below were checked on 2026-09-22. AWS can change prices, taxes, free-tier eligibility, bundle availability, and regional transfer rates. Run the readiness check and review the linked official pricing pages immediately before deployment.

## Expected recurring cost

The default MapleBridge gateway uses one Oregon Lightsail `nano_3_0` Linux instance with public IPv4:

| Item | Current price | Notes |
| --- | ---: | --- |
| Lightsail Nano instance | USD 5.00/month maximum | 2 vCPUs, 0.5 GB RAM, 20 GB SSD, and 1 TB monthly transfer allowance. Lightsail bills hourly up to the monthly plan price. |
| Attached Lightsail static IPv4 | USD 0 | Included while attached. An unattached static IP is chargeable, so deployment and deletion must not leave one orphaned. |
| CloudFormation with native `AWS::*` resources | USD 0 additional | The resources created by the stack are still billed normally. |
| SSM hybrid-node registration | USD 0 | No registration or per-node fee under the current hybrid-node model. |
| SSM Session Manager through 2026-09-29 | USD 0 | The transition period ends on 2026-09-30. |
| SSM Session Manager from 2026-09-30 | USD 0.05/session | Charged only when an interactive session is started on this hybrid node. |
| SSM Run Command through 2026-09-29 | USD 0 | The transition period ends on 2026-09-30. |
| SSM Run Command from 2026-09-30 | USD 0.002/invocation | Deployment, configuration, diagnostics, and Patch Manager operations can each invoke Run Command. |
| SSM Maintenance Windows | USD 0 additional | Patch operations that invoke Run Command still incur the hybrid-node invocation price after 2026-09-30. |

An always-on gateway with ten Run Command invocations and two interactive sessions in a month after 2026-09-30 would be approximately:

```text
Lightsail                 USD 5.00
10 Run Command calls      USD 0.02
2 Session Manager sessions USD 0.10
Estimated subtotal        USD 5.12/month
```

This estimate excludes taxes, transfer overage, snapshots, optional services, and accidental orphaned resources. Typical game traffic should fit comfortably inside 1 TB, but MapleBridge does not guarantee traffic volume.

## Cost controls

- The CloudFormation template defaults to `DeployGateway=false`, so its first phase creates no Lightsail instance.
- Readiness checks and local tests do not create billable resources.
- Keep the static IP attached to the instance; release it when permanently deleting the gateway.
- Use Run Command for repeatable automation and reserve Session Manager for interactive diagnosis.
- Review the exact stack target and current live bundle price before deployment.
- Deleting or stopping the instance is not yet an automated daily cost-saving strategy; the normal design assumes an always-on stable gateway.

Official references:

- [Amazon Lightsail pricing](https://aws.amazon.com/lightsail/pricing/)
- [Lightsail instance bundles](https://docs.aws.amazon.com/lightsail/latest/userguide/amazon-lightsail-bundles.html)
- [Lightsail data transfer allowance](https://docs.aws.amazon.com/lightsail/latest/userguide/amazon-lightsail-faq-data-transfer-allowance.html)
- [Lightsail static IP behavior and charges](https://docs.aws.amazon.com/lightsail/latest/userguide/understanding-static-ip-addresses-in-amazon-lightsail.html)
- [AWS Systems Manager pricing](https://aws.amazon.com/systems-manager/pricing/)
- [AWS CloudFormation pricing](https://aws.amazon.com/cloudformation/pricing/)
