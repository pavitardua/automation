import pandas as pd
import sqlalchemy
import requests
import argparse
import os
import sys
from datetime import datetime
from urllib.parse import urlparse

def get_sql_content(source):
    """
    Retrieves SQL content from a local file or a URL.
    """
    if source.startswith('http://') or source.startswith('https://'):
        print(f"Fetching SQL from URL: {source}")
        try:
            response = requests.get(source)
            response.raise_for_status()
            content = response.text
            
            # Check if content looks like HTML (common mistake with SharePoint/Drive links)
            if content.strip().lower().startswith(('<!doctype html', '<html')):
                print("WARNING: The fetched content appears to be HTML, not raw SQL.")
                print("If you are using a SharePoint/OneDrive/Google Drive link, ensure you are using the 'Direct Download' or 'Raw' link.")
                print("For SharePoint, try appending '&download=1' to the URL if it's a download link, but the provided link looks like a viewer link.")
                print("Proceeding, but this will likely fail...")
                
            return content
        except requests.exceptions.RequestException as e:
            print(f"Error fetching SQL from URL: {e}")
            sys.exit(1)
    else:
        print(f"Reading SQL from local file: {source}")
        if not os.path.exists(source):
            print(f"Error: File '{source}' not found.")
            sys.exit(1)
        try:
            with open(source, 'r') as f:
                return f.read()
        except Exception as e:
            print(f"Error reading local file: {e}")
            sys.exit(1)

def get_output_filename(source, prefix=None):
    """
    Generates the output filename based on the source or provided prefix.
    """
    current_date = datetime.now().strftime('%m_%d_%Y')
    
    if prefix:
        base_name = prefix
    else:
        # Extract filename from URL or path
        if source.startswith('http'):
            parsed = urlparse(source)
            path = parsed.path
            base_name = os.path.splitext(os.path.basename(path))[0]
        else:
            base_name = os.path.splitext(os.path.basename(source))[0]
            
    # Clean up base_name if it's empty or invalid
    if not base_name:
        base_name = "Report"
        
    return f"{base_name}_{current_date}.xlsx"

def main():
    parser = argparse.ArgumentParser(description='Run a SQL report and export to Excel.')
    parser.add_argument('sql_source', help='Path to local SQL file or URL to SQL file')
    parser.add_argument('--output-prefix', help='Prefix for the output Excel file (default: SQL filename)')
    
    args = parser.parse_args()
    
    # ---------------------------------------------------------
    # CONFIGURATION
    # ---------------------------------------------------------
    # Credentials should be provided via environment variables (e.g., Jenkins credentials binding)
    DB_SERVER = os.getenv('DB_SERVER')
    DB_DATABASE = os.getenv('DB_DATABASE')
    DB_USERNAME = os.getenv('DB_USERNAME')
    DB_PASSWORD = os.getenv('DB_PASSWORD')
    
    if not all([DB_SERVER, DB_DATABASE, DB_USERNAME, DB_PASSWORD]):
        print("Warning: One or more database environment variables are missing.")
        # We continue, assuming the user might have defaults or the connection string handles it, 
        # but usually this will fail if not set.

    # ---------------------------------------------------------
    # 1. SETUP DATABASE CONNECTION
    # ---------------------------------------------------------
    print("Setting up database connection...")
    
    # URL encode credentials to handle special characters like '@'
    from urllib.parse import quote_plus
    encoded_username = quote_plus(DB_USERNAME)
    encoded_password = quote_plus(DB_PASSWORD)
    
    # Connection string for MS SQL Server using ODBC Driver 17
    # You might need to adjust the driver depending on your environment
    connection_string = (
        f"mssql+pymssql://{encoded_username}:{encoded_password}@{DB_SERVER}/{DB_DATABASE}"
    )
    
    try:
        engine = sqlalchemy.create_engine(connection_string)
        connection = engine.connect()
        print("Database connection successful.")
    except Exception as e:
        print(f"Error connecting to database: {e}")
        sys.exit(1)

    # ---------------------------------------------------------
    # 2. GET SQL QUERY
    # ---------------------------------------------------------
    sql_query = get_sql_content(args.sql_source)

    # ---------------------------------------------------------
    # 3. EXECUTE QUERY AND FETCH DATA
    # ---------------------------------------------------------
    print("Executing query...")
    try:
        df = pd.read_sql(sql_query, connection)
        print(f"Query executed successfully. Retrieved {len(df)} rows.")
    except Exception as e:
        print(f"Error executing query: {e}")
        connection.close()
        sys.exit(1)
    finally:
        connection.close()

    # ---------------------------------------------------------
    # 4. EXPORT TO EXCEL
    # ---------------------------------------------------------
    output_filename = get_output_filename(args.sql_source, args.output_prefix)
    print(f"Exporting data to {output_filename}...")
    
    try:
        df.to_excel(output_filename, index=False)
        print("Export complete!")
    except Exception as e:
        print(f"Error exporting to Excel: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
