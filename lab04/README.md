# lab04 — Jenkins for DevOps Task Automation

## Project description

This lab starts Jenkins in Docker and uses it to run a CI pipeline for a PHP project.

- **Jenkins Controller** (`jenkins/jenkins:lts`) has the web interface, keeps the jobs and plans the
  builds.
- **SSH Agent** (`jenkins/ssh-agent` with PHP and Composer) runs the builds. The controller connects
  to it over SSH with a key pair.
- The pipeline gets the PHP project [timecapsule](https://github.com/bysinka-95-cloud/timecapsule),
  installs its dependencies with Composer and runs its unit tests with PHPUnit.

The pipeline runs only on agents with the label `php-agent`, so PHP is not necessary on the
controller.

## Project structure

| File                 | Purpose                                                                                                  |
|----------------------|----------------------------------------------------------------------------------------------------------|
| `docker-compose.yml` | Starts the services `jenkins-controller` and `ssh-agent` in the network `jenkins-network`.               |
| `Dockerfile`         | The agent image: `jenkins/ssh-agent` with `php-cli`, `php-xml`, `php-mbstring` and `composer`.           |
| `Jenkinsfile`        | The pipeline: stage `Install Dependencies` (git clone, `composer install`) and stage `Test` (`phpunit`). |
| `.gitignore`         | Keeps `secrets/` and `.env` out of git.                                                                  |
| `secrets/`           | The SSH key pair for the agent. You create it on your computer. Git does not track it.                   |
| `.env`               | `JENKINS_AGENT_SSH_PUBKEY` with the public key. You create it on your computer. Git does not track it.   |
| `README.md`          | This file.                                                                                               |

PHPUnit needs the PHP extensions `dom`, `mbstring`, `xml` and `xmlwriter`. The package `php-cli`
does not include them, so the `Dockerfile` also installs `php-xml` and `php-mbstring`. Composer
installs the project dependencies, so the image also has `composer`.

## Configure Jenkins Controller

1. Port 8080 must be free. The Currency Exchange Rate service from lab02 also uses port 8080. If it
   runs, stop it with `docker compose down` in its folder.

2. Start the controller:

   ```bash
   cd lab04
   docker compose up -d jenkins-controller
   ```

3. Get the initial administrator password:

   ```bash
   docker compose exec jenkins-controller cat /var/jenkins_home/secrets/initialAdminPassword
   ```

4. Open http://localhost:8080. Enter the password on the **Unlock Jenkins** page.

   ![Unlock Jenkins](img/unlock-jenkins.png)

5. Select **Install suggested plugins**. Create the first administrator user. Keep the Jenkins URL
   `http://localhost:8080/`.

   ![Jenkins dashboard](img/jenkins-dashboard.png)

The volume `jenkins_home` keeps the Jenkins data (settings, jobs, builds). The data stays when
Docker recreates the container.

## Configure SSH agent

1. Create the SSH key pair in the folder `secrets`:

   ```bash
   mkdir secrets
   cd secrets
   ssh-keygen -f jenkins_agent_ssh_key
   cd ..
   ```

   Keep the passphrase empty. If you set a passphrase, enter it also in the Jenkins credential.

2. Write the public key to the file `.env`:

   ```bash
   echo "JENKINS_AGENT_SSH_PUBKEY=$(cat secrets/jenkins_agent_ssh_key.pub)" > .env
   ```

   Docker Compose reads `.env` and gives the key to the agent container. The container adds the key
   to `/home/jenkins/.ssh/authorized_keys` of the user `jenkins`.

3. Restart the project. Docker Compose builds the agent image and starts both containers:

   ```bash
   docker compose up -d --build
   docker compose ps
   docker compose exec ssh-agent php -v
   ```

   ![Running containers](img/containers.png)

The private key `secrets/jenkins_agent_ssh_key` gives access to the agent. `.gitignore` keeps it out
of the repository.

## Connect SSH agent to Jenkins

1. Make sure that Jenkins has the plugin **SSH Build Agents** (old name: SSH Agents Plugin). Go to
   **Manage Jenkins > Plugins > Installed plugins**. The suggested plugins include this plugin. If
   the plugin is not in the list, install it on the **Available plugins** tab.

   ![SSH Build Agents plugin](img/ssh-plugin.png)

2. Add the SSH key. Go to **Manage Jenkins > Credentials > System > Global credentials > Add
   Credentials**:

   | Field       | Value                                                          |
   |-------------|----------------------------------------------------------------|
   | Kind        | SSH Username with private key                                  |
   | ID          | `jenkins-ssh`                                                  |
   | Description | `SSH key for jenkins build agent`                              |
   | Username    | `jenkins`                                                      |
   | Private Key | Enter directly: the content of `secrets/jenkins_agent_ssh_key` |

   Show the private key with `cat secrets/jenkins_agent_ssh_key`. Copy all lines, from
   `-----BEGIN OPENSSH PRIVATE KEY-----` to `-----END OPENSSH PRIVATE KEY-----`.

   ![SSH credential](img/credentials.png)

3. Add the agent node. Go to **Manage Jenkins > Nodes > New Node**. Enter the name `ssh-agent1`.
   Select **Permanent Agent**. Set these fields:

   | Field                          | Value                                       |
   |--------------------------------|---------------------------------------------|
   | Remote root directory          | `/home/jenkins/agent`                       |
   | Labels                         | `php-agent`                                 |
   | Launch method                  | Launch agents via SSH                       |
   | Host                           | `ssh-agent`                                 |
   | Credentials                    | `jenkins (SSH key for jenkins build agent)` |
   | Host Key Verification Strategy | Non verifying Verification Strategy         |

   The host name `ssh-agent` is the name of the service in `docker-compose.yml`. Docker resolves it
   in the network `jenkins-network`.

   ![Node configuration](img/node-config.png)

4. Save the node. Jenkins connects to the agent. The agent log shows `Agent successfully connected
   and online`, and the node list shows `ssh-agent1` without a red cross.

   ![Agent online](img/node-online.png)

## Create Jenkins pipeline

The project [timecapsule](https://github.com/bysinka-95-cloud/timecapsule) is a PHP application
without a framework. Its unit tests use PHPUnit 11:

| File                     | What it tests                                                                                                        |
|--------------------------|----------------------------------------------------------------------------------------------------------------------|
| `tests/HelpersTest.php`  | HTML escaping, text excerpts, UTC formatting, countdown text, settings from the environment, form field helpers.     |
| `tests/CapsulesTest.php` | How the code reads the open date, who can see a capsule, which errors the "New capsule" form shows.                  |
| `phpunit.xml`            | The test suite. `tests/bootstrap.php` loads only the files with pure functions, so the tests do not need a database. |

The [`Jenkinsfile`](Jenkinsfile) has two stages:

- **Install Dependencies** clones the repository and runs `composer install`. Composer installs the
  libraries from `composer.lock`, including PHPUnit.
- **Test** runs `vendor/bin/phpunit`. If a test fails, PHPUnit returns a non-zero exit code, and
  the build fails.

Create the pipeline:

1. On the dashboard, click **New Item**. Enter the name `Timecapsule Test`. Select **Pipeline**.
   Click **OK**.
2. In the section **Pipeline**, select the definition **Pipeline script**. Paste the content of
   `Jenkinsfile` into the field **Script**. Click **Save**.

   ![Pipeline configuration](img/pipeline-config.png)

3. Click **Build Now**. The build runs on the node `ssh-agent1`, because only this node has the
   label `php-agent`.

   ![Pipeline stages](img/pipeline-stages.png)

   The header shows `on built-in`, because the controller runs the pipeline script itself. The
   steps of the stages run on `ssh-agent1`, as the stage panel shows.

The end of the console output of a good build:

```text
+ vendor/bin/phpunit
PHPUnit 11.5.57 by Sebastian Bergmann and contributors.

Runtime:       PHP 8.4.27
Configuration: /home/jenkins/agent/workspace/Timecapsule Test/phpunit.xml

..............                                                    14 / 14 (100%)

Time: 00:00.003, Memory: 8.00 MB

OK (14 tests, 34 assertions)
...
Pipeline completed.
All stages completed successfully!
Finished: SUCCESS
```

![Console output](img/pipeline-console.png)

## Questions

### What are the advantages of using Jenkins for DevOps task automation?

- **Free and self-hosted.** Jenkins is free and open source. It runs on your own servers, so the
  code and the keys stay inside your infrastructure.
- **Pipeline as code.** The `Jenkinsfile` is a text file in git. Git keeps its history, as for the
  application code. You can review each change and restore an old version.
- **Distributed builds.** The controller only plans the work. The builds run on agents with
  different operating systems and tools. Several builds can run at the same time.
- **Many plugins:** Git and GitHub, Docker, Kubernetes, cloud providers, notifications, test
  reports.
- **Many triggers:** a push to the repository (webhook), polling of the repository, a schedule in
  cron syntax, other jobs, or a manual start.
- **Web interface and credentials.** The web interface shows the history of the builds, the console
  logs and the test results. The credential store keeps passwords and keys out of the pipeline code.

### What other types of Jenkins agents exist?

- **SSH agents** (this lab). The controller connects to the agent over SSH and starts the agent
  process.
- **Inbound agents** (JNLP or WebSocket). The agent opens the connection to the controller. An
  example is the image `jenkins/inbound-agent`. TCP port 50000 in `docker-compose.yml` is for these
  agents. This type is useful when the controller cannot connect to the agent, for example, when
  the agent is behind NAT.
- **Docker agents.** The pipeline starts a container for a build, for example
  `agent { docker { image 'php:8.4-cli' } }`. The Docker Cloud plugin creates agent containers when
  builds need them.
- **Kubernetes agents.** The Kubernetes plugin starts a pod for each build and deletes it after the
  build.
- **Cloud agents.** Plugins for Amazon EC2, Azure and other clouds start virtual machines when
  builds wait in the queue. The plugins stop idle machines.
- **Built-in node.** The controller can run builds itself. The Jenkins documentation does not
  recommend this, because a build then gets access to the files of the controller.

### What problems did you encounter when setting up Jenkins and how did you solve them?

- **The project had no unit tests.** The assignment needs a PHP project with unit tests. I added
  PHPUnit 11 to `require-dev` in timecapsule and wrote 14 tests for the functions that do not use
  the database.
- **`php-cli` is not sufficient for PHPUnit and Composer.** The Dockerfile from the assignment
  installs only `php-cli`. PHPUnit needs the extensions `dom`, `mbstring` and `xml`, and the agent
  needs Composer to install the dependencies. I added `php-xml`, `php-mbstring` and `composer` to
  the `Dockerfile`.
- **Host key verification.** The default strategy of a new SSH node looks for the agent in
  `/var/jenkins_home/.ssh/known_hosts` of the controller. This file does not exist, so the agent
  does not start. I selected **Non verifying Verification Strategy**. The agent runs in a local
  Docker network, so this is acceptable here. For a real server, use **Manually trusted key
  Verification Strategy**.
- **Port 8080 conflict.** The service from lab02 also listens on port 8080. If it runs, Docker
  cannot start Jenkins and reports `port is already allocated`. Stop the lab02 service first.
- **Git must not track the private key.** `.gitignore` contains `secrets/` and `.env`. The readme
  shows the commands to create them again.
