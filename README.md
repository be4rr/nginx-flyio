# 1つのAppの中でNginxとFlaskを実行しロードバランス

`app`がFlaskサーバーで，`web`がNginxサーバー．

## 状況
```bash
❯ fly status
App
  Name     = nginx-app-0514                                        
  Owner    = personal                                              
  Hostname = nginx-app-0514.fly.dev                                
  Image    = nginx-app-0514:deployment-01HXV50SB6SPNBY6AHCXQ1JWQ6  

Machines
PROCESS ID              VERSION REGION  STATE   ROLE    CHECKS  LAST UPDATED         
app     3d8d335ce06338  14      nrt     started                 2024-05-14T08:56:49Z
app     7842303a272408  14      nrt     started                 2024-05-14T09:00:37Z
web     e784994c2d0108  14      nrt     started                 2024-05-14T08:56:49Z
```

## `fly.toml`
`fly.toml`で，ポート開放していないコンテナの場合，`[[services]]`はいらない．Nginxの`[[services]]`だけになる．

## Flask

`main.py`でIPv6のホストであることを明示する．`0.0.0.0`はだめ．

```python
    app.run(host='::', port=5000) # ipv6
```

## Nginx
```nginx.conf
        location / {
            proxy_pass http://app.process.nginx-app-0514.internal:5000;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
```

このように設定すると，NginxからFlaskアプリへプロキシしてくれるが，毎回片方のアドレスにだけプロキシされてしまう．
Internal Addressについては[Private Networking · Fly Docs](https://fly.io/docs/networking/private-networking/#fly-io-internal-addresses)を参考．

```bash
root@e784994c2d0108:/app# host app.process.nginx-app-0514.internal
app.process.nginx-app-0514.internal has IPv6 address fdaa:2:17f0:a7b:22f:3b9:1937:2
app.process.nginx-app-0514.internal has IPv6 address fdaa:2:17f0:a7b:b4f1:4b4b:c16d:2
```


[Private Networking · Fly Docs](https://fly.io/docs/networking/private-networking/#discover-apps-through-dns-on-a-fly-machine) によると，Flyio内のDNSサーバーは`fdaa::3`にあるらしい．実際，次のように`fdaa::3`に内部のホスト名を問い合わせると，２つのIPv6アドレスが返ってきた．しかしGoogleのDNSサーバーに問い合わせても，ホスト名が見つからないと言われる．

```bash  
root@e784994c2d0108:/app# host app.process.nginx-app-0514.internal fdaa::3
Using domain server:
Name: fdaa::3
Address: fdaa::3#53
Aliases: 

app.process.nginx-app-0514.internal has IPv6 address fdaa:2:17f0:a7b:22f:3b9:1937:2
app.process.nginx-app-0514.internal has IPv6 address fdaa:2:17f0:a7b:b4f1:4b4b:c16d:2
root@e784994c2d0108:/app# host app.process.nginx-app-0514.internal 8.8.8.8
Using domain server:
Name: 8.8.8.8
Address: 8.8.8.8#53
Aliases: 

Host app.process.nginx-app-0514.internal not found: 3(NXDOMAIN)
```

次のようにすると，Nginxがロードバランスしてくれるらしい．

```nginx.conf
worker_processes 1;

events {
    worker_connections 1024;
}

http {
    upstream backend {
        server [fdaa:2:17f0:a7b:22f:3b9:1937:2];
        server [fdaa:2:17f0:a7b:b4f1:4b4b:c16d:2];
    }

    server {
        listen 80;
        server_name _;

        location / {
            proxy_pass http://backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
}
```

しかしIPアドレスがハードコードされてしまうので，次のようにすると良い（ってChatGPTが言ってた）．

```nginx.conf
worker_processes 1;

events {
    worker_connections 1024;
}

http {
    resolver [fdaa::3];  # FlyioのDNSを使用

    server {
        listen 80;
        server_name _;

        location / {
            set $backend "app.process.nginx-app-0514.internal";
            proxy_pass http://$backend:5000;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
}
```

詰まったのは`[fdaa::3]`でIPv6であることを明示すること．`fdaa::3`だとエラーが出る．

## もっと簡単な方法
多分NginxとFlaskでAppを分けて，`<app_name>.internal`でアクセスするのが簡単．ロードバランスもFly.ioがやってくれるはず．