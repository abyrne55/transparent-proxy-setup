# transparent-proxy-setup
Terraform scripts for setting up an AWS VPC with a [mitmproxy](https://mitmproxy.org/)-based transparent proxy

## Prerequisites
 * Terraform or OpenTofu
 * An AWS account with a credentials profile saved to "~/.aws/credentials"

## Setup
1. Clone this repo and `cd` into its root
2. Run `terraform init`
3. Copy/rename "terraform.tfvars.example" to "terraform.tfvars" and fill in the values according to the comments
4. Run `terraform apply`
5. Once you see "Apply complete!", wait an additional 3-5 minutes for the proxy server to initialize
6. Download the proxy's CA cert using the following command
```bash
curl --insecure $(terraform output -raw proxy_machine_cert_url) -o ./cacert.pem
```

And that's it! Anything you launch in the "proxied" subnet (`terraform output proxied_subnet_id`) will have its HTTP(S) traffic transparently routed through your proxy machine. Be sure to add the CA cert you downloaded to your proxied clients' trust store to avoid certificate errors, and be sure NOT to set any `HTTP[S]_PROXY` values (as you might for a non-transparent proxy).

Note that only  HTTP(S) traffic on TCP ports 80 and 443 are proxied; non-HTTP traffic (e.g, Splunk inputs) originating from inside the proxied subnet will almost always fail.

> [!TIP]  
> Run `terraform apply` again after making any changes to the files in this repo. Your proxy EC2 instance will probably be destroyed and recreated in the process, resulting in new IP addresses, CA certs, and passwords.

## Usage
### Launch a network verification tool in the proxied subnet
For example: [osd-network-verifier](https://github.com/openshift/osd-network-verifier). Run the following command on your workstation to launch an EC2 VM that will make a series of HTTPS requests that will be transparently proxied. Be sure to replace `default` with the name of your AWS credentials profile (see `profile` in "terraform.tfvars"). 
```bash
osd-network-verifier egress --profile=default --subnet-id=$(terraform output -raw proxied_subnet_id) --region=$(terraform output -raw region) --cacert=cacert.pem
```

### View/manipulate traffic flowing through the proxy
> [!NOTE]  
> The proxy webUI is HTTPS-secured but uses a runtime-generated self-signed certificate. As a result, you'll probably have to click-past some scary browser warnings (usually under "Advanced > Proceed to [...] (unsafe)"). This is also why we have to use curl's `--insecure` flag when downloading the proxy CA cert (which is unrelated to the webUI's self-signed cert).

Run the following command to print credentials you can use to access the mitmproxy's webUI in your browser
```bash
for V in url username password; do echo "$V: $(terraform output -raw proxy_webui_${V})"; done
```
If you're having trouble connecting to the webUI (other than certificate warnings; see above note), try disabling any VPNs or browser proxy extensions/configurations. Also ensure that your workstation's IP address is covered by the value you set for `developer_cidr_block` in "terraform.tfvars". As an insecure last resort, you can set `developer_cidr_block` to "0.0.0.0/0" to allow the entire internet to access your proxy machine.

### SSH into the proxy machine
Run the following command to log into the RHEL 9 machine hosting the proxy server. Add `-i [path to your private key]` to the command if the `proxy_machine_ssh_pubkey` you provided in "terraform.tfvars" does not correspond to your default private key (usually "~/.ssh/id_rsa"). See the paragraph above if you encounter connection issues.
```bash
ssh $(terraform output -raw proxy_machine_ssh_url) 
```
Once logged in, you can see the status of the proxy server using `sudo systemctl status mitmproxy`. The proxy's webUI is running on port 8081, but traffic from the outside world is reverse-proxied through [Caddy](https://caddyserver.com/) (via port 8443) first; you can check its status using `sudo systemctl status caddy`.

Remember that the proxy machine (and therefore changes you make to it via SSH) will likely be destroyed next time you run `terraform apply`. To make your changes more durable, add commands or [cloud-init](https://cloudinit.readthedocs.io/en/latest/reference/modules.html) directives to [assets/userdata.yaml.tpl](assets/userdata.yaml.tpl).

## Cleanup
To delete the reverse proxy server, the surrounding subnets/VPC, and all other AWS resources created by this script, simply run `terraform destroy`.




