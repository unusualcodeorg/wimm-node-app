# Moderm Backend Development - WhereIsMyMotivation

<!-- [![Docker Compose CI](https://github.com/janishar/wimm-node-app/actions/workflows/docker_compose.yml/badge.svg)](https://github.com/janishar/wimm-node-app/actions/workflows/docker_compose.yml) -->

### This is a complete production ready project to learn modern techniques and approaches to build a performant and secure backend API services. It is designed for web apps, mobile apps, and other API services.

## Framework
- Nest
- Express Node
- Typescript
- Mongoose
- Mongodb
- Redis
- JsonWebToken
- Jest
- Docker
- Multer

## Highlights
- API key support
- Token based Authentication
- Role based Authorization
- Database dump auto setup
- vscode template support
- Unit Tests
- Integration Tests
- 75% plus Test Coverage

# About Project
WhereIsMyMotivation is a concept where you see videos and quotes that can inspire you everyday. You will get information on great personalities and make them your percieved mentors. You can also suscribe to topics of your interests. 

You can track your happiness level and write down daily journals. You can also share things of interest from web to store in your motivation box.

Using this app can bring a little bit of happiness and energy to live an inspired life.

# API Framework Design
![Request - Response: Design](.resources/documentations/assets/api-structure.png)

# Installation Instruction

vscode is the recommended editor - dark theme 

### Get the repo 
```bash
# clone repository recursively
git clone https://github.com/janishar/wimm-node-app.git --recursive
```

### Install libraries
```bash
$ npm install
```

### Run Docker Compose
- Install Docker and Docker Compose. [Find Instructions Here](https://docs.docker.com/install/).

```bash
# install and start docker containers
docker-compose up -d
```
-  You will be able to access the api from http://localhost:3000

### Run Tests
```bash
docker exec -t app npm test`
```
If having any issue
- Make sure 3000 port is not occupied else change PORT in **.env** file.
- Make sure 27017 port is not occupied else change DB_PORT in **.env** file.
- Make sure 6379 port is not occupied else change REDIS_PORT in **.env** file.

## Run on the local machine
Change the following hosts in the **.env** and **.env.test**
- DB_HOST=localhost
- REDIS_HOST=localhost

### Best way to run is to use the vscode `Run and Debbug`

```bash
$ npm install
```

## Running the app

```bash
# development
$ npm run start

# watch mode
$ npm run start:dev

# production mode
$ npm run start:prod
```

## Test

```bash
# unit tests
$ npm run test

# e2e tests
$ npm run test:e2e

# test coverage
$ npm run test:cov
```

### Find this project useful ? :heart:
* Support it by clicking the :star: button on the upper right of this page. :v: