pipeline {
    agent any

    parameters {
        string(name: 'SQL_SOURCE', defaultValue: 'FORMS_REQUIREMENT_REPORT.sql', description: 'Path to local SQL file or URL')
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
        // DB_USERNAME = credentials('db-username-id')
        // DB_PASSWORD = credentials('db-password-id')
    }

    stages {
        stage('Setup Python') {
            steps {
                sh 'python3 -m venv venv'
                sh '. venv/bin/activate && pip install pandas sqlalchemy pymssql openpyxl requests'
            }
        }

        stage('Run Report Generation') {
            steps {
                // Ensure the script uses os.getenv() to read credentials
                // Usage: python3 run_sql_report.py <path_to_sql_file_or_url>
                sh ". venv/bin/activate && python3 run_sql_report.py '${params.SQL_SOURCE}'"
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
                to: "recipient@example.com", // Change this to the target email
                attachmentsPattern: "*.xlsx"
            )
        }
        failure {
            emailext (
                subject: "FAILED: Forms Requirement Report",
                body: "The report generation failed. Please check the Jenkins console logs.",
                to: "recipient@example.com"
            )
        }
    }
}
