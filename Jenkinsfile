pipeline {
    agent any

    // ── Poll GitHub every 5 minutes for changes ──────────────────────────────
    triggers {
        pollSCM('H/5 * * * *')
    }

    environment {
        // SonarQube server name (must match Jenkins global config)
        SONAR_SERVER      = 'SonarQube'
        // Production VM IP (must match ansible/inventory.ini)
        PROD_VM_IP        = '192.168.56.10'
        // The URL where the app will be deployed (used by ZAP scan)
        APP_URL           = "http://${PROD_VM_IP}:8080"
        // Ansible inventory file path inside the Jenkins workspace
        ANSIBLE_INVENTORY = 'ansible/inventory.ini'
        // Gradle JVM options to avoid OOM in container
        GRADLE_OPTS       = '-Xmx512m'
    }

    stages {

        // ── 1. Checkout ───────────────────────────────────────────────────────
        stage('Checkout') {
            steps {
                checkout scm
                echo "✅ Source checked out: ${env.GIT_COMMIT}"
            }
        }

        // ── 2. Build ──────────────────────────────────────────────────────────
        stage('Build') {
            steps {
                sh './gradlew clean build -x test'
            }
            post {
                success { echo "✅ Build passed" }
                failure { echo "❌ Build failed" }
            }
        }

        // ── 3. Unit Tests ─────────────────────────────────────────────────────
        stage('Test') {
            steps {
                sh './gradlew test'
            }
            post {
                always {
                    junit 'build/test-results/test/*.xml'
                }
            }
        }

        // ── 4. SonarQube Static Analysis ──────────────────────────────────────
        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv("${SONAR_SERVER}") {
                    sh '''
                        ./gradlew sonar \
                            -Dsonar.projectKey=spring-petclinic \
                            -Dsonar.projectName="Spring PetClinic"
                    '''
                }
            }
        }

        // ── 5. SonarQube Quality Gate ─────────────────────────────────────────
        stage('Quality Gate') {
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        // ── 6. Build Docker Image ─────────────────────────────────────────────
        stage('Docker Build') {
            steps {
                sh '''
                    docker build -t spring-petclinic:${BUILD_NUMBER} .
                    docker tag spring-petclinic:${BUILD_NUMBER} spring-petclinic:latest
                '''
            }
        }

        // ── 7. OWASP ZAP Security Scan ────────────────────────────────────────
        // ZAP scans the staging/local instance started from the JAR
        stage('ZAP Security Scan') {
            steps {
                script {
                    // Start the app temporarily on port 9999 for ZAP to scan
                    sh '''
                        nohup java -jar build/libs/*.jar \
                            --server.port=9999 \
                            > /tmp/petclinic-zap.log 2>&1 &
                        echo $! > /tmp/petclinic.pid
                        sleep 20   # Wait for Spring Boot to start
                    '''

                    // Run ZAP baseline scan from within the ZAP container
                    sh '''
                        docker run --rm \
                            --network devsecops-net \
                            -v ${WORKSPACE}:/zap/wrk:rw \
                            ghcr.io/zaproxy/zaproxy:stable \
                            zap-baseline.py \
                                -t http://jenkins:9999 \
                                -r zap-report.html \
                                -J zap-report.json \
                                --autooff \
                                -I
                    '''
                }
            }
            post {
                always {
                    // Stop the temporary app instance
                    sh 'kill $(cat /tmp/petclinic.pid) 2>/dev/null || true'

                    // Publish the HTML report in Jenkins
                    publishHTML(target: [
                        allowMissing         : true,
                        alwaysLinkToLastBuild: true,
                        keepAll              : true,
                        reportDir            : '.',
                        reportFiles          : 'zap-report.html',
                        reportName           : 'ZAP Security Report'
                    ])
                }
            }
        }

        // ── 8. Deploy to Production VM via Ansible ────────────────────────────
        stage('Deploy to Production') {
            steps {
                sshagent(['prod-vm-ssh-key']) {
                    // Copy the JAR to the VM, then run the Ansible playbook
                    sh '''
                        # Copy the built artifact to the production VM
                        scp -o StrictHostKeyChecking=no \
                            build/libs/*.jar \
                            ubuntu@${PROD_VM_IP}:/tmp/spring-petclinic.jar

                        # Run Ansible playbook to deploy and restart the service
                        ansible-playbook \
                            -i ${ANSIBLE_INVENTORY} \
                            ansible/deploy.yml \
                            --extra-vars "build_number=${BUILD_NUMBER}" \
                            -v
                    '''
                }
            }
        }

    } // end stages

    post {
        always {
            cleanWs()
        }
        success {
            echo "🚀 Pipeline succeeded! App deployed at ${APP_URL}"
        }
        failure {
            echo "💥 Pipeline failed. Check the logs above."
        }
    }
}
