pipeline {
    agent {
        label 'ansible-agent'
    }

    stages {
        stage('Clone PHP project') {
            steps {
                dir('timecapsule') {
                    git url: 'https://github.com/bysinka-95-cloud/timecapsule.git', branch: 'main'
                }
                // Pack only the files that are in git, without the .git folder
                sh 'git -C timecapsule archive --format=tar.gz -o "$WORKSPACE/timecapsule.tar.gz" HEAD'
            }
        }

        stage('Copy files to test server') {
            steps {
                // The repository with the deploy playbook
                dir('automation') {
                    git url: 'https://github.com/bysinka-95/automation.git', branch: 'lab05'
                }
                dir('automation/lab05/ansible') {
                    sh 'ansible-playbook -i hosts.ini deploy_php_project.yml --tags copy -e project_archive="$WORKSPACE/timecapsule.tar.gz"'
                }
            }
        }

        stage('Configure project on test server') {
            steps {
                dir('automation/lab05/ansible') {
                    sh 'ansible-playbook -i hosts.ini deploy_php_project.yml --tags configure'
                }
            }
        }
    }

    post {
        success {
            echo 'The project is available at http://localhost:8081'
        }
    }
}
