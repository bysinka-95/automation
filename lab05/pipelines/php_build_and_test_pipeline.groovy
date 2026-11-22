pipeline {
    agent {
        label 'php-agent'
    }

    stages {
        stage('Clone repository') {
            steps {
                git url: 'https://github.com/bysinka-95-cloud/timecapsule.git', branch: 'main'
            }
        }

        stage('Install Dependencies') {
            steps {
                sh 'composer install --no-interaction --no-progress'
            }
        }

        stage('Test') {
            steps {
                // A failed test makes the build UNSTABLE, so the stage "Report" still runs
                catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE') {
                    sh 'vendor/bin/phpunit --log-junit build/junit.xml'
                }
            }
        }

        stage('Report') {
            steps {
                junit 'build/junit.xml'
            }
        }
    }

    post {
        always {
            echo 'Pipeline completed.'
        }
        success {
            echo 'All stages completed successfully!'
        }
        failure {
            echo 'Errors detected in the pipeline.'
        }
    }
}
