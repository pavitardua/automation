pipeline {
    agent any

    // Parameter to select any SQL script (default is DailyVolume.sql)
    parameters {
        string(name: 'SQL_SOURCE', defaultValue: 'DailyVolume.sql', description: 'Path or URL to the SQL file to execute')
    }

    triggers {
        // Run daily at 6 AM (Server Time)
        // Note: TZ=America/New_York caused errors. Adjust hour if Server Time != EST.
        cron('H 6 * * *')
    }

    environment {
        // Define environment variables for database credentials
        // Best practice: Manage these in Jenkins Credentials and bind them here
        DB_SERVER = 'db-coachspan-prod-web-license-encrypted.cprkezy5vexx.us-east-1.rds.amazonaws.com'
        DB_DATABASE = 'master'
        // DB_USERNAME and DB_PASSWORD should be set in Jenkins Credentials
        // and bound to these environment variables using the 'credentials' helper
        DB_USERNAME = credentials('db-username-id')
        DB_PASSWORD = credentials('db-password-id')
    }

    stages {
        stage('Setup Python') {
            steps {
                script {
                    // If a cached venv already exists, just reuse it
                    if (fileExists('venv')) {
                        echo 'Reusing cached virtual environment'
                    } else {
                        echo 'Creating fresh virtual environment and installing deps'
                        sh 'python3 -m venv venv'
                        sh '. venv/bin/activate && pip install pandas sqlalchemy pymssql openpyxl requests'
                        // Cache it for the next build
                        stash name: 'venv', includes: 'venv/**'
                    }
                }
            }
        }

        stage('Run Report Generation') {
            steps {
                script {
                    // Determine which SQL file to run – default to DailyVolume.sql unless overridden by an env var
                    // Use the selected SQL source (default DailyVolume.sql)
                    def sqlSource = params.SQL_SOURCE
                    def cmd = ". venv/bin/activate && python3 run_sql_report.py '${sqlSource}'"
                    // If DailyVolume.sql, compute yesterday's date (UTC) and pass it
                    if (sqlSource.toLowerCase().contains('dailyvolume.sql')) {
                        def yesterday = new Date().minus(1).format('yyyy-MM-dd')
                        cmd += " '${yesterday}'"
                        echo "DailyVolume report will use date: ${yesterday}"
                    }
                    echo "Executing: ${cmd}"
                    sh cmd
                }
            }
        }
    }

    post {
        success {
            // Archive the Excel file so it's available in Jenkins
            archiveArtifacts artifacts: '*.xlsx', fingerprint: true
            
            // Email the report
            // Requires "Email Extension Plugin" in Jenkins
            emailext (
                subject: "Forms Requirement Report - ${currentBuild.currentResult}",
                body: "The Forms Requirement Report has been generated successfully. Please find the attached Excel file.",
                to: "pavitar.dua@gmail.com", // Change this to the target email
                attachmentsPattern: "*.xlsx"
            )
        }
        failure {
            emailext (
                subject: "FAILED: Forms Requirement Report",
                body: "The report generation failed. Please check the Jenkins console logs.",
                to: "pavitar.dua@gmail.com"
            )
        }
    }
}
