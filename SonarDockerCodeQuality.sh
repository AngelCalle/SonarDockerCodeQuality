# This script automates the process of launching Docker containers for SonarQube and PostgreSQL,
# creating a project in SonarQube, and analyzing a Java project with Maven and SonarQube.
# Usage: ./run.sh <project_key> <project_name> <main_branch> <analyze_token> <directory>

declare -g PROJECT=""
declare -g NAME=""
declare -g MAIN_BRANCH=""
declare -g ANALYZE=""
declare -g DIRECTORY=""

declare -g TOKEN
declare -g PASSWORD=admin
declare -g URL="http://localhost:9000"

declare -g COLOR_START="44;97m" # Blue / White
declare -g COLOR_FINISH="42;97m" # Green / White
declare -g COLOR_ERROR="41;97m" # Red / White

declare -g LANGUAGE=java
declare -g JAVA_VERSION=17
declare -g SONAR_VERSION=sonarqube:community
declare -g POSTGRES_VERSION=postgres:13
declare -g QUALITY_PROFILE=Quality_Profile_Java_Custom
declare -g QUALITY_GATES=Quality_Gates_Custom

cleanup() {
	printf "\033[$COLOR_START ------> Deleting the generated files. \033[0m\n"
	cd ..
	rm -f "$DIRECTORY/sonar-project.properties"
	rm -f docker-compose.yml
	printf "\033[$COLOR_FINISH ------> The whole process has finished successfully. \033[0m\n"
	exit 1
}

# Check dependencies
for cmd in docker-compose curl jq mvn; do
	if ! command -v $cmd &> /dev/null; then
		printf "\033[$COLOR_ERROR Error: $cmd is not installed. \033[0m\n"
		cleanup
	fi
done

# Define a function to handle the SIGINT signal (the signal sent when you press Ctrl+C),
handle_sigint() {
	# Try to stop all possible progress bars
	for i in {1..4}; do
		if [ -f "progress_$i.pid" ]; then
			stop_progress $i
		fi
	done
	cleanup
}

# Set the function handle_sigint to handle the SIGINT signal (the signal sent when you press Ctrl+C),
trap handle_sigint SIGINT

# Create an animated progress bar on the command line and save the PID.
start_progress() {
	while true; do
		for i in {1..3}; do
			printf "\rProcessing%s   " "$(printf "%${i}s"|tr ' ' '.')"
			printf ""
			sleep 1
		done
	done &

	printf $! > "progress_$1.pid"
}

# Stop the animation and clean up temporary files.
stop_progress() {
	if [ -f "progress_$1.pid" ]; then
		kill $(cat "progress_$1.pid") && rm "progress_$1.pid"
		printf "\n"
	fi
}

execute_and_check() {
	command_result=$("${@:1:$#-1}" > /dev/null 2>&1)
	command_exit_code=$?

	if [ $command_exit_code -ne 0 ]; then
		printf "\n\033[$COLOR_ERROR %s (Exit code: %s). \033[0m\n" "${@: -1}" "$command_exit_code"
		handle_sigint
		exit $command_exit_code
	fi
}

execute_and_check_response() {
	command_result=$(bash -c "${@:1:$#-1}" 2>&1)
	command_exit_code=$?

	if [ $command_exit_code -ne 0 ]; then
		printf "\n\033[$COLOR_ERROR %s (Exit code: %s). \033[0m\n" "${@: -1}" "$command_exit_code"
		handle_sigint
		exit $command_exit_code
	fi
	echo $command_result
}

validate_token_file() {
	if [[ -f "token_$NAME.txt" ]]; then
		TOKEN=$(< "token_$NAME.txt")
		if [[ -z "$TOKEN" ]]; then
			printf "\033[$COLOR_ERROR The token.txt file exists, but the value of TOKEN is null or empty.\033[0m\n"
			handle_sigint
		fi
	else
		printf "\n\033[$COLOR_ERROR The token_$NAME.txt file does not exist.\033[0m\n"
		handle_sigint
	fi

}

open_sonarqube() {
	if [[ "$OSTYPE" == "linux-gnu"* ]]; then
		xdg-open $URL
	elif [[ "$OSTYPE" == "darwin"* ]]; then
		open $URL
	elif [[ "$OSTYPE" == "cygwin" ]]; then
		cygstart $URL
	elif [[ "$OSTYPE" == "msys" ]]; then
		start $URL
	elif [[ "$OSTYPE" == "win32" ]]; then
		start $URL
	else
		printf "Unknown operating system."
	fi
}

run_maven() {
	printf "\033[$COLOR_START ------> Running Maven to verify and analyze the %s project with SonarQube. \033[0m\n" "$NAME"
	cd "$DIRECTORY"

	if [[ -z "$TOKEN" ]]; then
		printf "\033[$COLOR_ERROR Error: TOKEN is empty. Please provide a valid value. \033[0m\n"
		cleanup
	else
		mvn clean verify sonar:sonar -Dsonar.projectKey=$PROJECT -Dsonar.projectName=$NAME -Dsonar.host.url=$URL -Dsonar.token=$TOKEN
		printf "\033[$COLOR_FINISH ------> %s project analyzed by SonarQube. \033[0m\n" "$NAME"
	fi
}

generate_config_file() {
	printf "\033[$COLOR_START ------> Generating a sonar-project.properties configuration file for SonarQube. \033[0m\n"
	cat << EOF > "$DIRECTORY/sonar-project.properties"
sonar.projectKey=$DIRECTORY
sonar.projectName=$DIRECTORY
sonar.projectVersion=0.0.1

sonar.host.url=$URL

sonar.sources=src
sonar.tests=src/test
sonar.java.binaries=target/classes

sonar.core.codeCoveragePlugin=jacoco
sonar.junit.reportPaths=target/surefire-reports
sonar.coverage.jacoco.xmlReportPaths=target/site/jacoco/jacoco.xml

sonar.scm.git.repoUrl=.git
sonar.scm.username=tu-usuario
sonar.scm.password.secured=tu-contraseña-encriptada
sonar.scm.provider=git

sonar.sourceEncoding=UTF-8
sonar.language=$LANGUAGE
sonar.java.source=$JAVA_VERSION
sonar.qualitygate=$QUALITY_GATES
sonar.java.qualityProfile=$QUALITY_PROFILE

sonar.token=$TOKEN
EOF
	printf "\033[$COLOR_FINISH ------> sonar-project.properties file Generated \033[0m\n"
}

change_quality() {
	printf "\033[$COLOR_START ------> Change Java Quality Profiles in the %s project. \033[0m\n" "$NAME"
	start_progress 6
	execute_and_check curl -v -i -u admin:admin -X POST "$URL/api/qualitygates/select" -d "gateName=$QUALITY_GATE&projectKey=$PROJECT" "Error when modifying the Java Quality Gate of the $NAME project"
	execute_and_check curl -v -i -u admin:admin -X POST "$URL/api/qualityprofiles/add_project" -d "project=$PROJECT&qualityProfile=$QUALITY_PROFILE&language=$LANGUAGE" "Error when modifying the Java Quality Profiles of the $NAME project"
	sleep 10
	stop_progress 6
	printf "\033[$COLOR_FINISH ------> Modified Java Quality Profiles in the %s project. \033[0m\n" "$NAME"
}

generate_auth_token() {
	printf "\033[$COLOR_START ------> Generating an authentication token in SonarQube. \033[0m\n"
	start_progress 5
	TOKEN=$(execute_and_check_response "curl -s -u admin:${PASSWORD:-admin} -X POST '$URL/api/user_tokens/generate' -d 'login=admin' -d 'name=$PROJECT' | jq -r .token" "Authentication token not generated in SonarQube.")

	if [[ -n "$TOKEN" ]]; then
		printf "$TOKEN" > token_"$NAME".txt
	else
		printf "\033[$COLOR_ERROR Error: TOKEN is empty. Please provide a valid value. \033[0m\n"
		exit 1
	fi

	sleep 30
	stop_progress 5
	printf "\033[$COLOR_FINISH ------> Generated an authentication token in SonarQube. \033[0m\n"
}

create_project() {
	printf "\033[$COLOR_START ------> Creating the %s project in SonarQube. \033[0m\n" "$NAME"
	start_progress 4

	projects=$(execute_and_check_response "curl -s -u admin:admin $URL/api/projects/search" "Error listing projects.")
	project_exists=$(echo "$projects" | grep -c "\"key\":\"$NAME\"")

	if [ "$project_exists" -eq 0 ]; then
		execute_and_check curl -v -u admin:admin -X POST "$URL/api/projects/create?name=$NAME&project=$PROJECT" "The $NAME project was not created correctly in SonarQube."
	else
		printf "\n\033[$COLOR_ERROR Error: The $NAME project already exists in SonarQube.\033[0m\n"
		stop_progress 4
		cleanup
	fi

	sleep 10
	stop_progress 4
	printf "\033[$COLOR_FINISH ------> Created the %s project in SonarQube. \033[0m\n" "$NAME"
}

create_quality_profile() {
	printf "\033[$COLOR_START ------> Restoring the Quality Profile. \033[0m\n"
	start_progress 3
	exits_quality_profiles=$(execute_and_check_response "curl -s -u admin:admin -X GET $URL/api/qualityprofiles/search?language=$LANGUAGE" "Error getting java Quality Profiles.")

	if ! echo "$exits_quality_profiles" | jq -e --arg QUALITY_PROFILE "$QUALITY_PROFILE" '.profiles[] | select(.name == $QUALITY_PROFILE)' > /dev/null; then
		execute_and_check curl -v -i -s -u admin:admin -X POST -F backup=@$QUALITY_PROFILE.xml "$URL/api/qualityprofiles/restore" "Failed to restore Quality Profile."
		execute_and_check curl -v -s admin:admin -X POST "$URL/api/qualityprofiles/set_default?qualityProfile=$QUALITY_PROFILE&language=$LANGUAGE" "Error setting quality profile as default."
	else
		printf "\n\033[$COLOR_ERROR The Quality Profile $QUALITY_PROFILE already exists. \033[0m\n"
	fi

	sleep 10
	stop_progress 3
	printf "\033[$COLOR_FINISH ------> Quality Profile restored. \033[0m\n"
}

edit_quality_gates() {
	quality_gates=$(execute_and_check_response "curl -s -u admin:admin -X GET $URL/api/qualitygates/show?name=$QUALITY_GATES" "error when looking for the Quality Gates: $QUALITY_GATES.")

	coverage_id=$(echo $quality_gates | jq -r '.conditions[] | select(.metric=="new_coverage") | .id')
	duplicated_lines_density_id=$(echo $quality_gates | jq -r '.conditions[] | select(.metric=="new_duplicated_lines_density") | .id')

	execute_and_check curl -s -u admin:admin -X POST "$URL/api/qualitygates/update_condition" -d "id=$coverage_id&metric=new_coverage&op=LT&error=90" "Error when modifying the new_coverage property"
	execute_and_check curl -s -u admin:admin -X POST "$URL/api/qualitygates/update_condition" -d "id=$duplicated_lines_density_id&metric=new_duplicated_lines_density&op=GT&error=1.5" "Error when modifying the new_duplicated_lines_density property"
}

create_quality_gates() {
	printf "\033[$COLOR_START ------> Restoring the Quality Gates. \033[0m\n"
	start_progress 2

	exits_quality_gates=$(execute_and_check_response "curl -s -u admin:admin -X GET $URL/api/qualitygates/show?name=$QUALITY_GATES" "Error when looking for the Quality Gates: $QUALITY_GATES.")

	if  echo "$exits_quality_gates" | grep -q "\"errors\""; then
		execute_and_check curl -s -u admin:admin -X POST "$URL/api/qualitygates/create" -d "name=$QUALITY_GATES" "Error creating the Quality Gates: $QUALITY_GATES."
		execute_and_check curl -s -u admin:admin -X POST "$URL/api/qualitygates/set_as_default" -d "name=$QUALITY_GATES" "Error when defining the Quality Gates: $QUALITY_GATES
		as default."

		edit_quality_gates
	else
		printf "\n\033[$COLOR_ERROR The Quality Gates $QUALITY_GATES already exists. \033[0m\n"
	fi

	sleep 10
	stop_progress 2
	printf "\033[$COLOR_FINISH ------> Quality Gates restored. \033[0m\n"
}

build_containers() {
	printf "\033[$COLOR_START ------> Building the SonarQube and PostgreSQL containers. \033[0m\n"
	start_progress 1
	execute_and_check docker-compose up -d "The docker-compose command did not run successfully"
	sleep 80
	stop_progress 1
	printf "\033[$COLOR_FINISH ------> SonarQube and PostgreSQL containers are operational. \033[0m\n"
}

generate_docker_compose() {
	printf "\033[$COLOR_START ------> Generating docker-compose.yml file. \033[0m\n"
	cat << EOF > docker-compose.yml
version: "3"

services:
  sonarqube:
    image: $SONAR_VERSION
    container_name: sonarqube
    ports:
      - 9000:9000
    environment:
      SONAR_JDBC_URL: jdbc:postgresql://postgresql:5432/sonar
      SONAR_JDBC_USERNAME: sonar
      SONAR_JDBC_PASSWORD: sonar
      SONAR_ES_BOOTSTRAP_CHECKS_DISABLE: true
    volumes:
      - sonarqube_data:/opt/sonarqube/data
      - sonarqube_logs:/opt/sonarqube/logs
      - sonarqube_conf:/opt/sonarqube/conf
      - sonarqube_extensions:/opt/sonarqube/extensions
      - sonarqube_bundled-plugins:/opt/sonarqube/lib/bundled-plugins
    networks:
      - sonarnet
    depends_on:
      - postgresql
    restart: on-failure:5
    stop_grace_period: 5m

  postgresql:
    image: $POSTGRES_VERSION
    container_name: postgreSQL
    ports:
      - 5432:5432
    environment:
      POSTGRES_USER: sonar
      POSTGRES_PASSWORD: sonar
    volumes:
      - postgresql:/var/lib/postgresql
      - postgresql_data:/var/lib/postgresql/data
    networks:
      - sonarnet
    restart: on-failure:5
    stop_grace_period: 5m

networks:
  sonarnet:
    driver: bridge

volumes:
  sonarqube_data:
  sonarqube_logs:
  sonarqube_conf:
  sonarqube_extensions:
  sonarqube_bundled-plugins:
  postgresql:
  postgresql_data:
EOF
	printf "\033[$COLOR_FINISH ------> Generated docker-compose.yml file. \033[0m\n"
}

generate_environment() {
	generate_docker_compose
	build_containers
	create_quality_gates
	create_quality_profile
	create_project
	generate_auth_token
	change_quality
	generate_config_file
	run_maven
	open_sonarqube
	cleanup
}

check_directory_exists() {
	if [ ! -d "$1" ]; then
		printf "\033[$COLOR_FINISH The directory %s does not exist. \033[0m\n" "$1"
		cleanup
	fi
}

show_help() {
	printf "\nUsage: %s [OPTIONS]" $0
	printf "\nOptions:"
	printf "\n  --project, -p       Project Key: ${PROJECT:-Not provided}"
	printf "\n  --name, -n          Project Name: ${NAME:-Not provided}"
	printf "\n  --main-branch, -m   Main Branch: ${MAIN_BRANCH:-Not provided}"
	printf "\n  --analyze, -a       Analysis Token: ${ANALYZE:-Not provided}"
	printf "\n  --directory, -d     Project Directory: ${DIRECTORY:-Not provided}"

	printf "\n\n\n"
	printf "\nModes of operation:"
	printf "\n  1. All variables mode: This mode is used to start the project with Docker and SonarQube."
	printf "\n     You need to provide all the variables mentioned above."
	printf "\n"
	printf "\n  2. No variables mode: This mode is used to run a new SonarQube scan on the project."
	printf "\n     You don't need to provide any variables. Only the SonarQube scanner will be executed."

	printf "\n\n\n"
	printf "\nExample to generate the environment and analyze a project:"
	printf "\n  ./CarameloRun.sh carameloProject carameloName master carameloToken carameloPepe"
	printf "\n  or"
	printf "\n  ./CarameloRun.sh --project carameloProject --name carameloName --main-branch master --analyze carameloToken --directory carameloPepe"
	printf "\n  or"
	printf "\n  ./CarameloRun.sh -p carameloProject -n carameloName -m master -a carameloToken -d carameloPepe"

	printf "\n\n\n"
	printf "\nExample for reanalysis:"
	printf "\n  ./CarameloRun.sh carameloName carameloPepe"
	printf "\n  or"
	printf "\n  ./CarameloRun.sh --name carameloName --directory carameloPepe"
	printf "\n  or"
	printf "\n  ./CarameloRun.sh -n carameloName -d carameloPepe"

	exit 0
}

if [ "${1,,}" = "--help" ] || [ "${1,,}" = "-h" ]; then
	show_help

elif [[ $# -eq 2 ]] || [[ $# -eq 4 ]]; then
	if [[ $1 == "--name" ]] || [[ $1 == "-n" ]]; then
		NAME="$2"
	elif [[ $1 == "--directory" ]] || [[ $1 == "-d" ]]; then
		DIRECTORY="$2"
	else
		DIRECTORY="$1"
		NAME="$2"
	fi

	if [[ $# -eq 4 ]]; then
		if [[ $3 == "--directory" ]] || [[ $3 == "-d" ]]; then
			DIRECTORY="$4"
		else
			NAME="$4"
		fi
	fi

	check_directory_exists "$DIRECTORY"
	validate_token_file
	generate_config_file
	run_maven
	open_sonarqube
	cleanup

elif [ $# -eq 5 ]; then
	PROJECT="$1"
	NAME="$2"
	MAIN_BRANCH="$3"
	ANALYZE="$4"
	DIRECTORY="$5"
	check_directory_exists "$DIRECTORY"
	generate_environment

elif [ $# -eq 10 ]; then
	while getopts ":p:n:m:a:d:-:" opt; do
		case ${opt} in
			p ) PROJECT=$OPTARG ;;
			n ) NAME=$OPTARG ;;
			m ) MAIN_BRANCH=$OPTARG ;;
			a ) ANALYZE=$OPTARG ;;
			d ) DIRECTORY=$OPTARG ;;
			- )
				LONG_OPTARG="${OPTARG#*=}"
				case $OPTARG in
					project=?* ) PROJECT=$LONG_OPTARG ;;
					name=?* ) NAME=$LONG_OPTARG ;;
					main-branch=?* ) MAIN_BRANCH=$LONG_OPTARG ;;
					analyze=?* ) ANALYZE=$LONG_OPTARG ;;
					directory=?* ) DIRECTORY=$LONG_OPTARG ;;
					* ) printf "Invalid option: --$OPTARG" >&2; exit 1 ;;
				esac
				;;
			\? ) printf "invalid option: -$OPTARG" >&2; exit 1 ;;
			: ) printf "Option -$OPTARG requires an argument." >&2; exit 1 ;;
			* ) printf "Option not implemented: -$OPTARG" >&2; exit 1 ;;
		esac
	done
	shift $((OPTIND -1))
	check_directory_exists "$DIRECTORY"
	generate_environment

else
	printf "\033[$COLOR_ERROR Error: The number of variables is not correct, there are different configurations. \033[0m"
	printf "\n\033[$COLOR_ERROR Try using the help: --help -h \033[0m"
	exit 1
fi
