# Azure App Gateway + Linux VM

This project deploys:

- 1 Azure Resource Group
- 1 Virtual Network
- 2 Subnets (App Gateway requires its own)
- 1 Linux VM (Ubuntu)
- 1 Azure Application Gateway (Standard_v2)
- Nginx installed automatically on the VM

The App Gateway forwards HTTP traffic to the VM on port 80.

------------------------------------------------------------------------

## Architecture

```
Internet
   |
Public IP
   |
Application Gateway (Standard_v2)
   |
Backend Pool
   |
Linux VM (nginx)
```

------------------------------------------------------------------------

## Prerequisites

-   Azure CLI
-   Terraform >= 1.5
-   Logged into Azure:

``` bash
az login
```

Verify subscription:

``` bash
az account show --output table
```

------------------------------------------------------------------------

## Configuration

All configuration lives in `main.tf` inside the `locals {}` block:

``` hcl
locals {
  location  = "australiasoutheast"
  vm_size   = "Standard_D2s_v4"
}
```

I needed to play around with:

- `location` (due to capacity issues in australiaeast)
- `vm_size` (SKU unavailable in region)

------------------------------------------------------------------------

## Deploy

``` bash
terraform init
terraform apply
```

Provisioning takes ~5--10 minutes (App Gateway is slow).

------------------------------------------------------------------------

## Test

After apply completes:

``` bash
terraform output app_gateway_public_ip
```

Then test:

``` bash
curl http://<APP_GW_PUBLIC_IP>
```

You should see the nginx welcome page.

------------------------------------------------------------------------

## Destroy

To remove all resources:

``` bash
terraform destroy
```

------------------------------------------------------------------------

## License

MIT.
