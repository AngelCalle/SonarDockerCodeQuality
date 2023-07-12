# Code Quality Analysis Automation with SonarQube and Docker

## Description

This script automates the process of launching Docker containers for SonarQube and PostgreSQL, creating a project in
SonarQube, and analyzing a Java project with Maven and SonarQube.

## Requirements

-   Docker
-   Docker Compose
-   Curl
-   Jq
-   Maven

## Use

The script can be run in two ways:

1.  Full mode: This mode is used to start the project with Docker and SonarQube. You need to provide all the variables
    mentioned below.

    ```bash
    ./SonarDockerCodeQuality.sh <project_key> <project_name> <main_branch> <analysis_token> <directory>
    ```

    or

    ```bash
    ./SonarDockerCodeQuality.sh --project <project_key> --name <project_name> --main-branch <main_branch> --analyze <analysis_token> --directory <directory>
    ```

    or

    ```bash
    ./SonarDockerCodeQuality.sh -p <project_key> -n <project_name> -m <main_branch> -a <analysis_token> -d <directory>
    ```

2.  Variable-less mode: This mode is used to run a new SonarQube analysis on the project. You don't need to provide any
    variables. Only the SonarQube scanner will be executed.

    ```bash
    ./SonarDockerCodeQuality.sh --name <project_name> --directory <directory>
    ```

    or

    ```bash
    ./SonarDockerCodeQuality.sh -n <project_name> -d <directory>
    ```

## Variables

-   `project_key`: The unique key of the project to be created in SonarQube.
-   `project_name`: The name of the project to be created in SonarQube.
-   `main_branch`: The main branch of the project to be analyzed.
-   `analysis_token`: The authentication token for the SonarQube analysis.
-   `directory`: The directory of the project to be analyzed.

## Examples

Example with full variable identifier:

```bash
./SonarDockerCodeQuality.sh --project caramelo --name pepe --main-branch master --analyze true --directory user
```

Example with shortcuts in the variable identifier:

```bash
./SonarDockerCodeQuality.sh -p caramelo -n pepe -m master -a true -d usersA
```

## Helper

For more information on how to use the script, you can use the help option:

```bash
./SonarDockerCodeQuality.sh --help
```

or

```bash
./SonarDockerCodeQuality.sh -h
```

## Note

This script will delete the generated files after its execution. If you want to keep these files, you must modify the
script so that it doesn't remove them.
