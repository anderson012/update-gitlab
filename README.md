# Update Gitlab project
This is a simple project to update GitLab on a Linux server.  
The idea is to list the available versions directly from the GitLab repository in a simple way, download the image, and start the new container.  
This way, anyone with access to the server can update GitLab. 😄  


### Use example:
```shell
root@srv744381:~# update-gitlab
[INFO] Versão atual: 18.4.3
[INFO] Consultando tags disponíveis no Docker Hub...

[INFO] Selecione a versão desejada:
  [1] 18.5.0
  [2] 18.5.1

Digite o número da versão: 1
[INFO] Versão selecionada: 18.5.0
[INFO] Baixando imagem gitlab/gitlab-ce:18.5.0-ce.0...
18.5.0-ce.0: Pulling from gitlab/gitlab-ce
Digest: sha256:f7e992491db0c80a9a3f066c2c26e69b444307b5a8834e1bdde7929c4a74e97e
Status: Image is up to date for gitlab/gitlab-ce:18.5.0-ce.0
docker.io/gitlab/gitlab-ce:18.5.0-ce.0
[INFO] Parando containers existentes...
gitlab
[INFO] Renomeando container antigo...
[INFO] Criando novo container gitlab-new...
39be10f7c482bb8c709c951a68c8e5f10e25d772b2e1a46efc65656d27e985c2
[INFO] Aguardando 120s para o GitLab iniciar...
[INFO] Verificando status de saúde do GitLab...
[WARN] Tentativa 1 falhou. Aguardando 30s antes de tentar novamente...
[WARN] Tentativa 2 falhou. Aguardando 30s antes de tentar novamente...
[WARN] Tentativa 3 falhou. Aguardando 30s antes de tentar novamente...
[INFO] GitLab respondeu com sucesso!
[INFO] Finalizando atualização...
gitlab-old
[INFO] Removendo imagens antigas do GitLab...
[INFO] Removendo imagem gitlab/gitlab-ce:18.3.5-ce.0 (090fb3b1b575)...
[INFO] Removendo imagem gitlab/gitlab-ce:18.4.3-ce.0 (aafa230f0f8c)...
[INFO] Removendo imagem gitlab/gitlab-ce:18.2.8-ce.0 (12dd0ff0bcd3)...
[INFO] Removendo imagem gitlab/gitlab-ce:18.1.0-ce.0 (5d8154a38693)...
[INFO] Removendo imagem gitlab/gitlab-ce:18.0.0-ce.0 (6b1fc8ef33b7)...
[INFO] Removendo imagem gitlab/gitlab-ce:17.11.2-ce.0 (10a019b419fc)...
[INFO] Removendo imagem gitlab/gitlab-ce:17.11.0-ce.0 (e35105c0c1ab)...
[INFO] Atualização concluída com sucesso!
[INFO] Tempo total: 236s
```

Remember to make a backup before updating. (I never do, but don’t follow my example 🤓)  
Ideally, you should have customized the GitLab volumes to store data on your server instead of keeping it inside the container.

```shell
--volume "$GITLAB_HOME/config:/etc/gitlab" \
--volume "$GITLAB_HOME/logs:/var/log/gitlab" \
--volume "$GITLAB_HOME/data:/var/opt/gitlab"
```

### Requisites:
- A gitlab instance running in a docker container
- Bash
- Curl
- Jq
- Ssh access to the server
- Internet connection

### Packages Installation
```shell
sudo apt install curl jq
```

### Notes
To ensure your data is always stored in the same location, define a variable called GITLAB_HOME in your .bashrc or .zshrc file.
```shell
    export GITLAB_HOME="/opt/srv/gitlab" # mude conforme necessário
```

This helps keep your data consistent and prevents launching a new empty container.  
Check the variables defined in the script and modify them as needed.  

```shell
MAIN_DOMAIN="yourdomain.com.br"
CONTAINER_NAME="gitlab"
NEW_CONTAINER="gitlab-new"
IMAGE_BASE="gitlab/gitlab-ce"
DOMAIN="gitlab.${MAIN_DOMAIN}"
SSH_DOMAIN="gitssh.${MAIN_DOMAIN}"
WAIT_TIME=120
HEALTH_URL="https://${DOMAIN}/-/health" # needs to configure gitlab_rails['monitoring_whitelist'] in gitlab.rb (**https://docs.gitlab.com/administration/monitoring/ip_allowlist/**)
```
- Check the container execution command, as it may differ from yours — modify it if necessary.

````shell
docker run --detach \
    --hostname "$DOMAIN" \
    --publish 4443:443 \
    --publish 8080:80 \
    --publish 222:22 \
    --name "$NEW_CONTAINER" \
    --restart always \
    --env GITLAB_OMNIBUS_CONFIG="external_url 'https://${DOMAIN}'; gitlab_rails['gitlab_shell_ssh_port'] = 222; gitlab_rails['gitlab_ssh_host'] = '${SSH_DOMAIN}'; letsencrypt['enable'] = false" \
    --env EXTERNAL_URL="https://${DOMAIN}" \
    --volume "$GITLAB_HOME/config:/etc/gitlab" \
    --volume "$GITLAB_HOME/logs:/var/log/gitlab" \
    --volume "$GITLAB_HOME/data:/var/opt/gitlab" \
    --shm-size 256m \
    "$image"
````

#### New additions and improvements are always welcome — feel free to submit a PR!