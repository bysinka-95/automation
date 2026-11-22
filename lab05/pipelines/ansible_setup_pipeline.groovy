pipeline {
    agent {
        label 'ansible-agent'
    }

    stages {
        stage('Clone repository') {
            steps {
                git url: 'https://github.com/bysinka-95/automation.git', branch: 'lab05'
            }
        }

        stage('Run playbook') {
            steps {
                dir('lab05/ansible') {
                    sh 'ansible-playbook -i hosts.ini setup_test_server.yml'
                }
            }
        }
    }
}
