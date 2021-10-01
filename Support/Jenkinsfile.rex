pipeline {
    agent { label 'zowe-agent' }
    environment {
        // z/OS Host Information
        ZOWE_OPT_HOST=credentials('eosHost')            
    }
    stages {
        stage('local setup') {
            steps {
                sh 'node --version'
                sh 'npm --version'
                sh 'zowe --version'
                sh 'zowe plugins list'
                sh 'npm install gulp-cli -g'
                sh 'npm install'

                //Create zosmf profile, env vars will provide host, user, and password details
                sh 'zowe profiles create zosmf Jenkins --port 443 --ru false --host dummy --user dummy --password dummy'
            }
        }
        stage('Download Maintenance') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'eosCreds', usernameVariable: 'ZOWE_OPT_USER', passwordVariable: 'ZOWE_OPT_PASSWORD')]) {
                    sh 'rexx rexxfile download'
                }
            }
        }
        stage('Upload Maintenance') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'eosCreds', usernameVariable: 'ZOWE_OPT_USER', passwordVariable: 'ZOWE_OPT_PASSWORD')]) {
                    sh 'rexx rexxfile upload'
                }
            }
        }
        stage('Receive') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'eosCreds', usernameVariable: 'ZOWE_OPT_USER', passwordVariable: 'ZOWE_OPT_PASSWORD')]) {
                    sh 'rexx rexxfile receive'
                }
                archiveArtifacts artifacts: 'job-archive/**/*.*'
            }
        }
        stage('applyCheck') {
            steps {
                script {
                    def actions = readJSON file: 'holddata/actions.json'
                    if (actions.remainingHolds) {
                        input message: 'Unresolved holds detected. Please review the results of the receive job in the job-archive/receive artifacts. Proceed to applyCheck?'
                    }
                }
                withCredentials([usernamePassword(credentialsId: 'eosCreds', usernameVariable: 'ZOWE_OPT_USER', passwordVariable: 'ZOWE_OPT_PASSWORD')]) {
                    sh 'rexx rexxfile applyCheck'
                }
                archiveArtifacts artifacts: 'job-archive/**/*.*'
            }
        }
        stage('Apply') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'eosCreds', usernameVariable: 'ZOWE_OPT_USER', passwordVariable: 'ZOWE_OPT_PASSWORD')]) {
                    sh 'rexx rexxfile apply'
                }
                archiveArtifacts artifacts: 'job-archive/**/*.*'
            }
        }
        stage('Deploy') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'eosCreds', usernameVariable: 'ZOWE_OPT_USER', passwordVariable: 'ZOWE_OPT_PASSWORD')]) {
                    //To deploy the maintenace, an OPS profile needs to be created since profile options are not exposed on the command line
                    sh 'zowe profiles create ops Jenkins --host $ZOWE_OPT_HOST --port 6007 --protocol https --user $ZOWE_OPT_USER --password $ZOWE_OPT_PASSWORD --ru false'
                    sh 'rexx rexxfile stop'
                    sh 'rexx rexxfile copy'
                    script {
                        def actions = readJSON file: 'holddata/actions.json'
                        if (actions.restart) {
                            sh 'rexx rexxfile restartWorkflow'
                        }
                    }
                    sh 'rexx rexxfile apf'
                    sh 'rexx rexxfile start'
                }
            }
        }
        stage('Test') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'eosCreds', usernameVariable: 'ZOWE_OPT_USER', passwordVariable: 'ZOWE_OPT_PASSWORD')]) {
                    sh 'npm test'
                }
            }
        }
    }
    post {
        always {
            archiveArtifacts artifacts: '*-archive/**/*.*, holddata/actions.json' 
            publishHTML([allowMissing: false,
                alwaysLinkToLastBuild: true,
                keepAll: true,
                reportDir: 'mochawesome-report',
                reportFiles: 'mochawesome.html',
                reportName: 'Test Results',
                reportTitles: 'Test Report'
                ])
        }
    }
}
