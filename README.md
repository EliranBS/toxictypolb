# toxictypolb

`toxictypolb` is a Java 8 Spring Boot application based on ToxicTypoApp. It exposes the original ToxicTypo web UI and suggestion API, plus a name storage API:

- `GET /api/name`
- `POST /api/name` with form parameter `name=<value>`

The application listens on port `8080`.

## Build

Use the Maven wrapper to build and test the application:

```bash
./mvnw verify
```

The Spring Boot jar is generated in the `target/` directory.

## Docker

This repository includes a multi-stage `Dockerfile`:

1. A Maven/Java 8 build stage runs `./mvnw -B verify`.
2. A lightweight Java 8 runtime stage copies only the generated jar and `entrypoint.sh`.
3. The runtime image exposes port `8080` and starts the app with `exec java -jar /app/app.jar`.

### Local Docker testing

Build the Docker image:

```bash
docker build -t toxictypolb:local .
```

Run the container on port `8080`:

```bash
docker run --rm --name toxictypolb-local -p 8080:8080 toxictypolb:local
```

In another terminal, test the name API:

```bash
curl -fsS http://localhost:8080/api/name
curl -fsS -X POST http://localhost:8080/api/name -d "name=server1"
curl -fsS http://localhost:8080/api/name
```

The final `GET /api/name` response should include `"name":"server1"`.

## Jenkins Multibranch Pipeline for GitHub

`Jenkinsfile` is written for a GitHub-hosted repository connected to Jenkins as a Multibranch Pipeline job. Jenkins should discover branches from GitHub and run `checkout scm` for the branch that triggered the build.

The pipeline performs the following flow:

1. Checkout from GitHub.
2. Build and test with `./mvnw verify`.
3. Build the Docker image.
4. Run the image locally and verify:
   - the main web application responds on port `8080`;
   - `GET /api/name` works;
   - `POST /api/name -d "name=server1"` works;
   - a follow-up `GET /api/name` returns the stored name.
5. Run E2E tests from `src/test/e2e_test.py` with a `python:2.7-slim` Docker container.
6. On the `master` branch only:
   - authenticate to AWS ECR;
   - tag and push the image to ECR;
   - perform a rolling deployment to two EC2 instances behind an ALB target group.

## Jenkins credentials

Create these Jenkins credentials before enabling deployment stages:

- `jenkins-aws-credentials` or your chosen value for `AWS_CREDENTIALS_ID`:
  - Type: AWS credentials supported by the Jenkins AWS Credentials plugin.
  - Permissions: ECR push/pull, `elasticloadbalancing:DeregisterTargets`, `elasticloadbalancing:RegisterTargets`, `elasticloadbalancing:DescribeTargetHealth`, and `ec2:DescribeInstances`.
- `jenkins-ec2-ssh-key` or your chosen value for `SSH_KEY_CREDENTIAL_ID`:
  - Type: SSH username with private key, or SSH private key credential compatible with the Jenkins SSH Agent plugin.
  - The public key must be authorized on both EC2 instances.

Do not store AWS secret keys, SSH private keys, or any other sensitive values directly in this repository.

## Jenkins and AWS variables

Update the placeholder values in `Jenkinsfile` or override them through Jenkins folder/job configuration for non-sensitive values:

- `AWS_REGION`
- `AWS_ACCOUNT_ID`
- `AWS_CREDENTIALS_ID`
- `ECR_REPOSITORY_NAME`
- `ALB_TARGET_GROUP_ARN`
- `EC2_INSTANCE_1_ID`
- `EC2_INSTANCE_2_ID`
- `SSH_USER`
- `SSH_KEY_CREDENTIAL_ID`
- `ECR_IMAGE_TAG`

The EC2 instances should have Docker and AWS CLI installed. They should use an IAM instance profile that allows ECR pulls, or another secure non-repository authentication mechanism for AWS CLI access. The remote deployment command logs in to ECR, pulls the new image, stops the existing `toxictypolb` container if present, and starts the replacement container on port `8080`.

## Rolling deployment design

The `master` branch deployment updates one target at a time:

1. Deregister EC2 instance 1 from the ALB target group and wait until it is deregistered.
2. SSH to EC2 instance 1, pull the new ECR image, and restart the Docker container.
3. Register EC2 instance 1 back to the target group and wait until it is healthy.
4. Repeat the same deregister, update, restart, register, and health-wait flow for EC2 instance 2.

This keeps one EC2 instance available behind the ALB while the other instance is being updated.
