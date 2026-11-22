# lab05 — Ansible Playbooks for Server Configuration

## Project description

This lab adds Ansible to the Jenkins setup from [lab04](../lab04). Jenkins runs three pipelines:

1. Build and test the PHP project [timecapsule](https://github.com/bysinka-95-cloud/timecapsule)
   with Composer and PHPUnit.
2. Configure the test server with an Ansible playbook: Apache2, PHP and PostgreSQL.
3. Deploy the PHP project to the test server with a second Ansible playbook.

Docker Compose starts four containers in the network `jenkins-network`:

| Container            | Image                      | Purpose                                                                    |
|----------------------|----------------------------|----------------------------------------------------------------------------|
| `jenkins-controller` | `jenkins/jenkins:lts`      | The web interface of Jenkins at http://localhost:8080. Keeps and plans the jobs. |
| `ssh-agent`          | `Dockerfile.ssh_agent`     | Builds and tests the PHP project. Jenkins label: `php-agent`.              |
| `ansible-agent`      | `Dockerfile.ansible_agent` | Runs the Ansible playbooks. Jenkins label: `ansible-agent`.                |
| `test-server`        | `Dockerfile.test_server`   | The Ubuntu server that Ansible configures. The project is at http://localhost:8081. |

All connections use SSH keys:

| From            | To              | User      | Key                                 |
|-----------------|-----------------|-----------|-------------------------------------|
| Jenkins         | `ssh-agent`     | `jenkins` | `secrets/jenkins_agent_ssh_key`     |
| Jenkins         | `ansible-agent` | `jenkins` | `secrets/jenkins_ansible_agent_key` |
| `ansible-agent` | `test-server`   | `ansible` | `secrets/ansible_test_server_key`   |

## Project structure

| File                                      | Purpose                                                                       |
|-------------------------------------------|-------------------------------------------------------------------------------|
| `compose.yaml`                            | The four services, the volumes and the network.                               |
| `Dockerfile.ssh_agent`                    | The PHP agent from lab04: `jenkins/ssh-agent` with PHP and Composer.          |
| `Dockerfile.ansible_agent`                | Ubuntu with sshd, Java, git and Ansible.                                      |
| `Dockerfile.test_server`                  | Ubuntu with sshd, sudo, Python and the user `ansible`.                        |
| `ansible/hosts.ini`                       | The inventory: how Ansible connects to the test server.                       |
| `ansible/group_vars/test_servers.yml`     | The variables for both playbooks: folders, URL, database settings.            |
| `ansible/setup_test_server.yml`           | The playbook that configures the test server.                                 |
| `ansible/deploy_php_project.yml`          | The playbook that deploys the PHP project.                                    |
| `pipelines/php_build_and_test_pipeline.groovy` | The pipeline that builds and tests the PHP project.                      |
| `pipelines/ansible_setup_pipeline.groovy` | The pipeline that runs `setup_test_server.yml`.                               |
| `pipelines/php_deploy_pipeline.groovy`    | The pipeline that runs `deploy_php_project.yml`.                              |
| `.gitignore`                              | Keeps `secrets/` and `.env` out of git.                                       |
| `secrets/`, `.env`                        | The SSH keys and the public key for `ssh-agent`. You create them on your computer. Git does not track them. |

## Prepare the SSH keys and start the containers

1. Stop the containers of lab04. They use port 8080 and the same container names:

   ```bash
   cd lab04
   docker compose down
   ```

2. Create the three key pairs in the folder `secrets`. Keep each passphrase empty. The pipelines
   cannot enter a passphrase.

   ```bash
   cd lab05
   mkdir secrets
   ssh-keygen -f secrets/jenkins_agent_ssh_key
   ssh-keygen -f secrets/jenkins_ansible_agent_key
   ssh-keygen -f secrets/ansible_test_server_key
   echo "JENKINS_AGENT_SSH_PUBKEY=$(cat secrets/jenkins_agent_ssh_key.pub)" > .env
   ```

   Docker reads the keys when it builds the images:

   - `ssh-agent` gets its public key from `.env`, as in lab04.
   - `Dockerfile.ansible_agent` copies `jenkins_ansible_agent_key.pub` to `authorized_keys` of the
     user `jenkins`. It also copies the private key `ansible_test_server_key` for Ansible.
   - `Dockerfile.test_server` copies `ansible_test_server_key.pub` to `authorized_keys` of the user
     `ansible`.

   The image `ansible-agent` contains a private key. Do not push this image to a registry.

3. Build the images and start the containers:

   ```bash
   docker compose up -d --build
   docker compose ps
   ```

   ![Running containers](img/containers.png)

## 1. Configure Jenkins Controller

1. Get the initial administrator password:

   ```bash
   docker compose exec jenkins-controller cat /var/jenkins_home/secrets/initialAdminPassword
   ```

2. Open http://localhost:8080. Enter the password. Select **Install suggested plugins**. Create the
   first administrator user.

3. Go to **Manage Jenkins > Plugins > Available plugins**. Install these plugins:

   | Plugin                     | Purpose                                                    |
   |----------------------------|------------------------------------------------------------|
   | Docker                     | Starts Jenkins agents in Docker containers.                |
   | Docker Pipeline            | Lets a pipeline build images and run steps in containers.  |
   | GitHub Integration         | Starts builds from GitHub events, for example pull requests. |
   | SSH Agent                  | Gives SSH keys from the credentials to the steps of a pipeline. |

   The assignment asks for these plugins. The pipelines of this lab do not use them. The pipelines
   need **SSH Build Agents** and **JUnit**, which are in the suggested plugins.

   ![Installed plugins](img/plugins.png)

## 2. Configure SSH agent

The SSH agent is the same as in lab04. `Dockerfile.ssh_agent` is the `Dockerfile` of lab04:
`jenkins/ssh-agent` with `php-cli`, `php-xml`, `php-mbstring` and `composer`.

1. Go to **Manage Jenkins > Credentials > System > Global credentials > Add Credentials**. Add the
   key for the SSH agent:

   | Field       | Value                                                          |
   |-------------|----------------------------------------------------------------|
   | Kind        | SSH Username with private key                                  |
   | ID          | `jenkins-ssh`                                                  |
   | Username    | `jenkins`                                                      |
   | Private Key | Enter directly: the content of `secrets/jenkins_agent_ssh_key` |

2. Go to **Manage Jenkins > Nodes > New Node**. Add the node `ssh-agent1` with these settings:

   | Field                          | Value                               |
   |--------------------------------|-------------------------------------|
   | Type                           | Permanent Agent                     |
   | Remote root directory          | `/home/jenkins/agent`               |
   | Labels                         | `php-agent`                         |
   | Launch method                  | Launch agents via SSH               |
   | Host                           | `ssh-agent`                         |
   | Credentials                    | the key `jenkins-ssh`               |
   | Host Key Verification Strategy | Non verifying Verification Strategy |

## 3. Create Ansible agent

`Dockerfile.ansible_agent` builds the Ansible agent from `ubuntu:24.04`:

- `openssh-server`: Jenkins connects to the agent over SSH.
- `openjdk-21-jre-headless`: Jenkins starts its agent process with Java.
- `git`: the pipelines clone the repositories.
- `ansible`: ansible-core 2.16 with the collections `community.general` and `community.postgresql`.
  The playbooks use modules from these collections.
- The user `jenkins` with `authorized_keys` for the key from Jenkins. The private key
  `/home/jenkins/.ssh/ansible_test_server_key` lets Ansible connect to the test server.

Connect the agent to Jenkins:

1. Add the credential `jenkins-ansible`. Use the kind **SSH Username with private key**, the
   username `jenkins` and the content of `secrets/jenkins_ansible_agent_key`.

   ![Credentials](img/credentials.png)

2. Add the node `ansible-agent1`. Use the settings of `ssh-agent1` with these changes:

   | Field       | Value                     |
   |-------------|---------------------------|
   | Labels      | `ansible-agent`           |
   | Host        | `ansible-agent`           |
   | Credentials | the key `jenkins-ansible` |

   ![Ansible agent node](img/ansible-agent-node.png)

3. Make sure that both nodes are online on the page **Manage Jenkins > Nodes**.

   ![Nodes](img/nodes.png)

4. Make sure that the Ansible agent can log in to the test server as the user `ansible`. The
   command prints `ansible`:

   ```bash
   docker compose exec -u jenkins ansible-agent \
     ssh -i /home/jenkins/.ssh/ansible_test_server_key -o StrictHostKeyChecking=no ansible@test-server whoami
   ```

   ![SSH from the Ansible agent](img/ansible-ssh-check.png)

## 4. Create test server

`Dockerfile.test_server` builds the test server from `ubuntu:24.04`:

- `openssh-server`: Ansible connects to the server over SSH. The file
  `/etc/ssh/sshd_config.d/keys-only.conf` turns off password logins and root logins.
- `python3`: Ansible runs its modules with Python on the server. The image `ubuntu:24.04` has no
  Python.
- `sudo`: the playbooks use `become: true` for root tasks. The user `ansible` can use `sudo` without
  a password.
- The user `ansible` with `authorized_keys` for `secrets/ansible_test_server_key.pub`.

The container has no systemd. When the container starts, its command starts PostgreSQL and Apache
(if the playbook installed them). Then it runs `sshd` in the foreground.

The test server has only SSH at the start. The Ansible playbook installs all other software.

## 5. Ansible playbook

### Inventory

`ansible/hosts.ini` puts the test server in the group `test_servers`:

```ini
[test_servers]
test-server ansible_host=test-server ansible_user=ansible ansible_ssh_private_key_file=/home/jenkins/.ssh/ansible_test_server_key
```

- `ansible_host=test-server`: the name of the container in the Docker network.
- `ansible_user=ansible`: Ansible logs in as the user `ansible`.
- `ansible_ssh_private_key_file`: the key in the image of the Ansible agent.
- `ansible_ssh_common_args`: Docker makes a new host key each time it builds the test server, so
  Ansible does not check the host key. Use `known_hosts` for a real server.

`ansible/group_vars/test_servers.yml` has the variables for both playbooks. Ansible reads it for the
hosts of the group `test_servers`. It contains `app_dir`, `app_url`, `php_version` and the database
settings.

### Playbook `setup_test_server.yml`

The playbook configures the test server. All tasks run as root (`become: true`).

| Task                                     | Module                                | What it does                                                    |
|------------------------------------------|---------------------------------------|-----------------------------------------------------------------|
| Install Apache2                          | `ansible.builtin.apt`                 | Updates the package list and installs `apache2`.                |
| Install PHP, the PHP extensions and Composer | `ansible.builtin.apt`             | Installs `libapache2-mod-php`, `php-cli`, `php-pgsql`, `php-mbstring`, `php-xml`, `composer` and `unzip`. |
| Configure PHP for the project            | `ansible.builtin.copy`                | Writes `99-timecapsule.ini`: upload limits, no errors for visitors. |
| Install PostgreSQL                       | `ansible.builtin.apt`                 | Installs `postgresql`, `python3-psycopg2` and `acl`.            |
| Start PostgreSQL                         | `ansible.builtin.service`             | Starts the database server.                                     |
| Create the database user                 | `community.postgresql.postgresql_user`| Creates the user `timecapsule` with its password.               |
| Create the database                      | `community.postgresql.postgresql_db`  | Creates the database `timecapsule`.                             |
| Create the project folder                | `ansible.builtin.file`                | Creates `/var/www/timecapsule/public`.                          |
| Configure the Apache virtual host        | `ansible.builtin.copy`                | Writes `timecapsule.conf`. `DocumentRoot` is `public/`. `FallbackResource` sends all other URLs to `index.php`. |
| Enable the project site                  | `ansible.builtin.command`             | Runs `a2ensite timecapsule` if `sites-enabled/timecapsule.conf` does not exist. |
| Disable the default site                 | `ansible.builtin.command`             | Runs `a2dissite 000-default` if `sites-enabled/000-default.conf` exists. |
| Start Apache                             | `ansible.builtin.service`             | Starts Apache.                                                  |
| Reload Apache (handler)                  | `ansible.builtin.service`             | Reloads Apache when the PHP settings or the site changed.       |

The playbook is idempotent. The first run on a new test server shows `changed=13`. The second run
shows `changed=0`, because the server already has the correct state.

### Playbook `deploy_php_project.yml`

The playbook deploys the PHP project. The pipeline gives it the archive of the project in the
variable `project_archive`. The tags divide the playbook into two pipeline stages:

| Task                                     | Tag         | Module                       | What it does                                         |
|------------------------------------------|-------------|------------------------------|------------------------------------------------------|
| Copy the project files to the test server | `copy`     | `ansible.builtin.unarchive`  | Copies the archive to the server and extracts it to `/var/www/timecapsule`. |
| Install the Composer packages            | `configure` | `community.general.composer` | Runs `composer install --no-dev --optimize-autoloader`. |
| Write the settings of the project        | `configure` | `ansible.builtin.copy`       | Writes `.env` with the database settings. Only root and Apache can read it. |
| Create the database tables               | `configure` | `ansible.builtin.command`    | Runs `php bin/init-db.php`. The script creates only the tables that do not exist. |
| Let Apache write the sessions and the uploads | `configure` | `ansible.builtin.file`  | Makes `www-data` the owner of `storage/`.            |

## 6–8. Jenkins pipelines

The Ansible pipelines clone the branch `lab05` of this repository. Push the branch before you run
them.

Create a job for each file in `pipelines/`:

1. On the dashboard, click **New Item**. Enter the name of the file without `.groovy`, for example
   `php_build_and_test_pipeline`. Select **Pipeline**. Click **OK**.
2. In the section **Pipeline**, select the definition **Pipeline script**. Paste the content of the
   file into the field **Script**. Click **Save**.

Run the jobs in this sequence:

| Job                           | Agent           | Stages                                                                 |
|-------------------------------|-----------------|------------------------------------------------------------------------|
| `php_build_and_test_pipeline` | `php-agent`     | Clone repository, Install Dependencies, Test, Report                   |
| `ansible_setup_pipeline`      | `ansible-agent` | Clone repository, Run playbook                                         |
| `php_deploy_pipeline`         | `ansible-agent` | Clone PHP project, Copy files to test server, Configure project on test server |

### Build and test the PHP project

- **Clone repository** clones timecapsule.
- **Install Dependencies** runs `composer install`.
- **Test** runs `vendor/bin/phpunit --log-junit build/junit.xml`. If a test fails, the build becomes
  UNSTABLE, and the next stage still runs.
- **Report** sends `build/junit.xml` to the `junit` step. The job page then shows the **Test Result**
  with 14 passed tests.

![Test report](img/test-report.png)

### Configure the test server

- **Clone repository** clones this repository.
- **Run playbook** runs `ansible-playbook -i hosts.ini setup_test_server.yml` in `lab05/ansible`.

![Ansible setup pipeline](img/pipeline-ansible-setup.png)

### Deploy the PHP project

- **Clone PHP project** clones timecapsule. `git archive` packs the files that are in git into
  `timecapsule.tar.gz`. The archive does not contain the folder `.git`.
- **Copy files to test server** clones this repository for the playbook. Then it runs
  `deploy_php_project.yml` with the tag `copy`.
- **Configure project on test server** runs `deploy_php_project.yml` with the tag `configure`.

![Deploy pipeline](img/pipeline-deploy.png)

## 9. Test the deployed project

Open http://localhost:8081. The login page of TimeCapsule opens. Register a user and create a
capsule. The page **My capsules** shows the new capsule.

![TimeCapsule on the test server](img/app.png)

The address http://localhost:8081/health checks the database connection:

```json
{"status":"ok","db":"ok","hostname":"5fd80a689b65"}
```

![Health check](img/app-health.png)

The test server keeps the installed software in its container. `docker compose down` deletes the
container. After a new start, run `ansible_setup_pipeline` and `php_deploy_pipeline` again.

## Questions

### What are the advantages of using Ansible for server configuration?

- **No agent on the server.** Ansible needs only SSH and Python on the server. The test server of
  this lab has only `openssh-server`, `sudo` and `python3` before the first run.
- **Idempotency.** A playbook describes the state of the server, not a list of commands. The second
  run of `setup_test_server.yml` changes nothing.
- **Readable code in git.** Playbooks are YAML files. You can review them and keep their history
  like the application code.
- **Modules instead of shell scripts.** Modules install packages, write files, start services and
  create databases. Each module reports `ok` or `changed`.
- **Inventory and variables.** One playbook can configure many servers. Groups and `group_vars` keep
  the settings for each environment.
- **Handlers.** Apache reloads only when its configuration changed.
- **Many collections.** Collections add modules for databases, clouds, network devices and
  containers.
- **Secrets in the repository.** Ansible Vault encrypts passwords, so you can keep them in git.
  This lab keeps `db_password` as plain text in `group_vars`. On a real server, use Vault.

### What other Ansible modules exist for configuration management?

This lab uses `apt`, `copy`, `file`, `service`, `command`, `unarchive`, `postgresql_user`,
`postgresql_db` and `composer`. Other modules for configuration management:

| Module                              | Purpose                                                        |
|-------------------------------------|----------------------------------------------------------------|
| `ansible.builtin.template`          | Writes a file from a Jinja2 template with variables.           |
| `ansible.builtin.lineinfile`        | Adds, changes or deletes one line in a file.                   |
| `ansible.builtin.blockinfile`       | Adds or changes a block of lines in a file.                    |
| `ansible.builtin.user`, `group`     | Creates and changes users and groups.                          |
| `ansible.builtin.systemd_service`   | Starts, stops and enables systemd services.                    |
| `ansible.builtin.package`, `dnf`    | Installs packages on other Linux distributions.                |
| `ansible.builtin.git`               | Clones a repository on the server.                             |
| `ansible.builtin.get_url`, `uri`    | Downloads files and sends HTTP requests.                       |
| `ansible.builtin.cron`              | Adds and deletes cron jobs.                                    |
| `ansible.posix.authorized_key`      | Adds SSH keys to `authorized_keys` of a user.                  |
| `ansible.posix.synchronize`         | Copies folders with `rsync`.                                   |
| `community.general.ini_file`        | Changes settings in INI files, for example `php.ini`.          |
| `community.general.ufw`, `ansible.posix.firewalld` | Configures the firewall.                        |
| `community.mysql.mysql_db`, `mysql_user` | Creates MySQL databases and users.                        |
| `community.docker.docker_container` | Starts and stops Docker containers.                            |

### What problems did you encounter when creating the Ansible playbook and how did you solve them?

- **The PHP project needs PostgreSQL.** The assignment lists only Apache and PHP. TimeCapsule keeps
  its data in PostgreSQL. I added PostgreSQL, the database user and the database to
  `setup_test_server.yml`. `deploy_php_project.yml` writes `.env` and creates the tables.
- **The PostgreSQL modules run as the user `postgres`.** Ansible must give the files of the module
  to this user. For this, the server needs the package `acl`, and the modules need
  `python3-psycopg2`. The playbook installs both. Ansible still shows a warning about `remote_tmp`
  for the user `postgres`, but the tasks complete.
- **The container has no systemd.** The module `service` uses the init scripts of Apache and
  PostgreSQL. These services do not start again when the container restarts. The command of
  `Dockerfile.test_server` starts them.
- **The image `ubuntu:24.04` has no Python.** Ansible modules need Python on the server.
  `Dockerfile.test_server` installs `python3`.
- **The host key of the test server changes after each build.** SSH stops the connection when a
  known host key changes. `hosts.ini` turns off the host key check for this local test server.
- **The containers of lab04 use the same names.** Docker showed
  `The container name "/jenkins-controller" is already in use`. Docker keeps the names of stopped
  containers too. `docker compose down` in lab04 deletes these containers.
