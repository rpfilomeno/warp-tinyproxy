# warp-tinyproxy

[![Docker Pulls](https://img.shields.io/docker/pulls/rpfilomeno/warp)](https://hub.docker.com/r/rpfilomeno/warp)
[![Docker Pulls](https://img.shields.io/docker/pulls/rpfilomeno/warp)](https://hub.docker.com/r/rpfilomeno/warp)  

Run official [Cloudflare WARP](https://1.1.1.1/) client in Docker.

> [!NOTE]
> Cannot guarantee that the [TinyProxy](https://github.com/tinyproxy/tinyproxy) and WARP client contained in the image are the latest versions. If necessary, please [build your own image](#build).


## Usage

### Start the container

To run the WARP client in Docker, just write the following content to `docker-compose.yml` and run `docker-compose up -d`.

```yaml
version: "3"

services:
  warp:
    image: rpfilomeno/warp
    container_name: warp
    restart: always
    # add removed rule back (https://github.com/opencontainers/runc/pull/3468)
    device_cgroup_rules:
      - 'c 10:200 rwm'
    ports:
      - "1080:1080"
    environment:
      - WARP_SLEEP=2
      # - WARP_LICENSE_KEY= # optional
      # - WARP_ENABLE_NAT=1 # enable nat
    cap_add:
      # Docker already have them, these are for podman users
      - MKNOD
      - AUDIT_WRITE
      # additional required cap for warp, both for podman and docker
      - NET_ADMIN
    sysctls:
      - net.ipv6.conf.all.disable_ipv6=0
      - net.ipv4.conf.all.src_valid_mark=1
      # uncomment for nat
      # - net.ipv4.ip_forward=1
      # - net.ipv6.conf.all.forwarding=1
      # - net.ipv6.conf.all.accept_ra=2
    volumes:
      - ./data:/var/lib/cloudflare-warp
      - ./tinyproxy:/etc/tinyproxy
    logging:
      options:
        max-size: "10m"
        max-file: "3"
    healthcheck:
      # Healthcheck command for curl. Change port if you changed PORT environment variable above.
      test:
        [
          "CMD",
          "curl",
          "-I",
          "-H",
          "Host: tinyproxy.stats",
          "http://localhost:1080",
        ]
      # If you use use BasicAuth use this line instead, and replace <username>:<password> with your credentials and comment out the line above.
      # test: ["CMD", "curl", "-u", "<username>:<password>", "-I", "-H", "Host: tinyproxy.stats", "http://localhost:8888"]
      interval: 5m
      timeout: 10s
      retries: 1
```

Try it out to see if it works:

```bash
curl -x http://127.0.0.1:1080 https://cloudflare.com/cdn-cgi/trace
```

If the output contains `warp=on` or `warp=plus`, the container is working properly. If the output contains `warp=off`, it means that the container failed to connect to the WARP service.

### Configuration

You can configure the container through the following environment variables:

- `WARP_SLEEP`: The time to wait for the WARP daemon to start, in seconds. The default is 2 seconds. If the time is too short, it may cause the WARP daemon to not start before using the proxy, resulting in the proxy not working properly. If the time is too long, it may cause the container to take too long to start. If your server has poor performance, you can increase this value appropriately.
- `WARP_LICENSE_KEY`: The license key of the WARP client, which is optional. If you have subscribed to WARP+ service, you can fill in the key in this environment variable. If you have not subscribed to WARP+ service, you can ignore this environment variable.
- `REGISTER_WHEN_MDM_EXISTS`: If set, will register consumer account (WARP or WARP+, in contrast to Zero Trust) even when `mdm.xml` exists. You usually don't need this, as `mdm.xml` are usually used for Zero Trust. However, some users may want to adjust advanced settings in `mdm.xml` while still using consumer account.
- `BETA_FIX_HOST_CONNECTIVITY`: If set, will add checks for host connectivity into healthchecks and automatically fix it if necessary. See [host connectivity issue](docs/host-connectivity.md) for more information.
- `WARP_ENABLE_NAT`: If set, will work as warp mode and turn NAT on. You can route L3 traffic through `warp-docker` to Warp. See [nat gateway](docs/nat-gateway.md) for more information.

Data persistence: Use the host volume `./data` and `./tinyproxy` to persist the data of the WARP client. You can change the location of this directory or use other types of volumes. If you modify the `WARP_LICENSE_KEY`, please delete the `./data` directory so that the client can detect and register again.


## Build

You can use Github Actions to build the image yourself.

1. Fork this repository.
2. Create necessary variables and secrets in the repository settings:
   1. variable `REGISTRY`: for example, `docker.io` (Docker Hub)
   2. variable `IMAGE_NAME`: for example, `rpfilomeno/warp`
   3. variable `DOCKER_USERNAME`: for example, `rpfilomeno`
   4. secret `DOCKER_PASSWORD`: generate a token in Docker Hub and fill in the token
3. Manually trigger the workflow `Build and push image` in the Actions tab.

This will build the image with the latest version of WARP client and GOST and push it to the specified registry. You can also specify the version of GOST by giving input to the workflow. Building image with custom WARP client version is not supported yet.


## Common problems

### Proxying UDP or even ICMP traffic

Not Supported

### How to connect from another container

You may want to use the proxy from another container and find that you cannot connect to `127.0.0.1:1080` in that container. This is because the `docker-compose.yml` only maps the port to the host, not to other containers. To solve this problem, you can use the service name as the hostname, for example, `warp:1080`. You also need to put the two containers in the same docker network.

#### Method 1: Environment Variables (Recommended)

Add these environment variables to your container:

```yaml
services:
  your-app:
    image: your-image
    environment:
      - ALL_PROXY=http://warp:1080
      - HTTPS_PROXY=http://warp:1080
      - HTTP_PROXY=http://warp:1080
      - NO_PROXY=localhost,127.0.0.1,.local,.internal
    depends_on:
      warp-socks5:
        condition: service_healthy
```

**Test from your container:**
```bash
docker-compose exec your-app curl https://www.cloudflare.com/cdn-cgi/trace
```

#### Method 2: Shared Network Stack

Share the WARP container's network:

```yaml
services:
  your-app:
    image: your-image
    network_mode: "service:warp"
    # Use localhost:1080 as the proxy address
```

**Note:** You cannot expose ports when using `network_mode`.

#### Method 3: From Host Machine

Access the proxy from your host:

```bash
# Using curl
curl -x http://localhost:1080 https://example.com

# Using wget
wget -e use_proxy=yes -e http_proxy=localhost:1080 https://example.com

# Configure system-wide (Linux/macOS)
export HTTPS_PROXY=http://warp:1080
export HTTP_PROXY=http://warp:1080
export NO_PROXY=localhost,127.0.0.1,.local,.internal
```

#%## Method 4: Application-Specific Configuration

**Python (requests):**
```python
proxies = {
    'http': 'http://warp:1080',
    'https': 'http://warp:1080'
}
response = requests.get('https://example.com', proxies=proxies)
```



**Go:**
```go
proxyURL, _ := url.Parse("http://warp:1080")
transport := &http.Transport{Proxy: http.ProxyURL(proxyURL)}
client := &http.Client{Transport: transport}
```

### "Operation not permitted" when open tun

Error like `{ err: Os { code: 1, kind: PermissionDenied, message: "Operation not permitted" }, context: "open tun" }` is caused by [a updated of containerd](https://github.com/containerd/containerd/releases/tag/v1.7.24). You need to pass the tun device to the container following the [instruction](docs/tun-not-permitted.md).

#
### Container runs well but cannot connect from host

This issue often arises when using Zero Trust. You may find that you can run `curl --socks5-hostname 127.0.0.1:1080 https://cloudflare.com/cdn-cgi/trace` inside the container, but cannot run this command outside the container (from host or another container). This is because Cloudflare WARP client is grabbing the traffic. See [host connectivity issue](docs/host-connectivity.md) for solutions.

