#!/usr/bin/env pwsh

Write-Host "====================================="
Write-Host "  Node + Fastify + PrismaORM + DDD + Hexagonal"
Write-Host "====================================="
Write-Host ""

# ============================================
# 1. INFORMACION BASICA DEL PROYECTO
# ============================================
$PROJECT_NAME = Read-Host "Nombre del proyecto"
$AUTHOR_NAME = Read-Host "Autor del proyecto"

# Generar puerto aleatorio para el servicio (evita conflictos con otros proyectos)
$SERVER_PORT = Get-Random -Minimum 3001 -Maximum 65535

# ============================================
# 2. SELECCION DE BASE DE DATOS
# ============================================
Write-Host ""
Write-Host "Selecciona las bases de datos a usar (separadas por comas):"
Write-Host "1) SQL Server"
Write-Host "2) MySQL"
Write-Host "3) PostgreSQL"
Write-Host "4) MongoDB"
Write-Host "5) SQLite"
$DB_SELECTION = Read-Host "Ejemplo: 1,3 para SQL Server y PostgreSQL"

# Parsear seleccion de DBs
$USE_SQLSERVER = $false
$USE_MYSQL = $false
$USE_POSTGRES = $false
$USE_MONGODB = $false
$USE_SQLITE = $false

$DB_ARRAY = $DB_SELECTION -split ','
foreach ($db in $DB_ARRAY) {
    switch ($db.Trim()) {
        '1' { $USE_SQLSERVER = $true }
        '2' { $USE_MYSQL = $true }
        '3' { $USE_POSTGRES = $true }
        '4' { $USE_MONGODB = $true }
        '5' { $USE_SQLITE = $true }
    }
}

# ============================================
# 3. SELECCION DE SISTEMA DE MENSAJERIA
# ============================================
Write-Host ""
Write-Host "Selecciona el sistema de mensajeria:"
Write-Host "1) AWS SQS"
Write-Host "2) RabbitMQ"
$MESSAGING_OPTION = Read-Host "Opcion (1 o 2)"

$USE_SQS = $false
$USE_RABBITMQ = $false

switch ($MESSAGING_OPTION) {
    '1' { $USE_SQS = $true }
    '2' { $USE_RABBITMQ = $true }
    default {
        Write-Host "Opcion invalida, usando SQS por defecto"
        $USE_SQS = $true
    }
}

# ============================================
# 4. CONFIGURACION DE EDITOR
# ============================================
Write-Host ""
$INDENT_SIZE = Read-Host "Indent size (2 o 4, default 4)"
if ([string]::IsNullOrWhiteSpace($INDENT_SIZE)) {
    $INDENT_SIZE = 4
}

Write-Host ""
Write-Host "Indent style:"
Write-Host "1) Tab (default)"
Write-Host "2) Space"
$INDENT_STYLE_OPTION = Read-Host "Opcion (1 o 2)"

$INDENT_STYLE = "tab"
$USE_TABS = $true

switch ($INDENT_STYLE_OPTION) {
    '2' { $INDENT_STYLE = "space"; $USE_TABS = $false }
    default { $INDENT_STYLE = "tab"; $USE_TABS = $true }
}

# ============================================
# CREAR ESTRUCTURA DEL PROYECTO
# ============================================
New-Item -ItemType Directory -Path $PROJECT_NAME | Out-Null
Set-Location $PROJECT_NAME

Write-Host ""
Write-Host "Creando package.json..."
npm init -y > $null 2>&1
npm pkg set name="$PROJECT_NAME"
npm pkg set author="$AUTHOR_NAME"
npm pkg set version="1.0.0"
npm pkg set description="Servicio con DDD + Hexagonal + Fastify + PrismaORM"
npm pkg set main="dist/index.js"
npm pkg set scripts.dev="ts-node-dev --respawn --transpile-only src/index.ts"
npm pkg set scripts.build="tsc"
npm pkg set scripts.start="node dist/index.js"

# ============================================
# INSTALACION DE DEPENDENCIAS BASE
# ============================================
Write-Host "Instalando dependencias base..."
$DEPS = @(
    "@fastify/cors",
    "@fastify/formbody",
    "@fastify/multipart",
    "@fastify/swagger",
    "@fastify/swagger-ui",
    "@prisma/client",
    "prisma",
    "class-transformer",
    "class-validator",
    "csv-parse",
    "dotenv",
    "fastify",
    "helmet",
    "jsonwebtoken",
    "reflect-metadata",
    "typedi",
    "winston",
    "winston-daily-rotate-file"
)

# Agregar dependencias segun DB seleccionada
if ($USE_SQLSERVER) { $DEPS += "mssql" }
if ($USE_MYSQL) { $DEPS += "mysql2" }
if ($USE_POSTGRES) { $DEPS += "pg" }
if ($USE_MONGODB) { $DEPS += "mongodb", "mongoose" }

# Agregar dependencias segun mensajeria
if ($USE_SQS) { $DEPS += "@aws-sdk/client-secrets-manager", "@aws-sdk/client-sqs" }
if ($USE_RABBITMQ) { $DEPS += "amqplib" }

npm install @DEPS

# ============================================
# DEPENDENCIAS DE DESARROLLO
# ============================================
Write-Host "Instalando dependencias de desarrollo..."
$DEVDEPS = @(
    "typescript",
    "ts-node-dev",
    "@types/node",
    "@types/jsonwebtoken",
    "eslint",
    "eslint-plugin-import",
    "eslint-plugin-simple-import-sort",
    "eslint-plugin-unused-imports",
    "@typescript-eslint/parser",
    "@typescript-eslint/eslint-plugin",
    "husky",
    "lint-staged"
)

if ($USE_RABBITMQ) { $DEVDEPS += "@types/amqplib" }

npm install -D @DEVDEPS

# ============================================
# ESTRUCTURA DE CARPETAS
# ============================================
Write-Host "Creando estructura de carpetas DDD + Hexagonal..."
$folders = @(
    "src/domain/repositories",
    "src/domain/valueObjects",
    "src/domain/entities",
    "src/domain/models",
    "src/domain/services",
    "src/domain/ports",
    "src/infrastructure/bootstrap",
    "src/infrastructure/db/repositories",
    "src/infrastructure/db/migrations",
    "src/infrastructure/db/migrations/prisma",
    "src/infrastructure/logging",
    "src/infrastructure/swagger",
    "src/infrastructure/swagger/schemas",
    "src/infrastructure/adapters",
    "src/infrastructure/messaging",
    "src/infrastructure/http/routes",
    "src/infrastructure/http/controllers",
    "src/infrastructure/http/responses",
    "src/infrastructure/http/requests",
    "src/application/dto",
    "src/application/usecases",
    "src/application/commands",
    "src/application/ports",
    "src/application/interfaces",
    "src/application/events",
    "src/application/results",
    "test/unit",
    "test/integration"
)

foreach ($folder in $folders) {
    New-Item -ItemType Directory -Path $folder | Out-Null
}

# ============================================
# ARCHIVOS ENV
# ============================================
Write-Host "Creando archivos env..."
"PORT=$SERVER_PORT" | Set-Content "env.development"
"PORT=$SERVER_PORT" | Set-Content "env.production"
"PORT=$SERVER_PORT" | Set-Content "env.testing"
"PORT=$SERVER_PORT" | Set-Content "env.local"

# ============================================
# TSCONFIG
# ============================================
Write-Host "Creando tsconfig.json..."
$tsconfigContent = @"
{
	"compilerOptions": {
    	"target": "ES2021",
    	"module": "CommonJS",
    	"outDir": "dist",
    	"rootDir": "src",
    	"strict": true,
    	"esModuleInterop": true,
    	"emitDecoratorMetadata": true,
    	"experimentalDecorators": true,
		"baseUrl": "src",
		"paths": {
			"@domain/*": ["domain/*"],
    		"@application/*": ["application/*"],
    		"@infrastructure/*": ["infrastructure/*"]
		},
		"ignoreDeprecations": "6.0"
  	}
}
"@

$tsconfigContent | Set-Content "tsconfig.json"

# ============================================
# LOAD ENV VARS
# ============================================
$loadEnvVarsContent = @'
import { config } from "dotenv";
config();
'@

$loadEnvVarsContent | Set-Content "src/load-env-vars.ts"

# ============================================
# LOGGER SERVICE
# ============================================
$loggerServiceContent = @'
import fs from "fs";
import path from "path";
import winston from "winston";
import DailyRotateFile from "winston-daily-rotate-file";

export enum LogLevel {
  ERROR = "error",
  WARN = "warn",
  INFO = "info",
  HTTP = "http",
  DEBUG = "debug",
}

export interface LogOptions {
  context?: string;
  service?: string;
  userId?: string;
  metadata?: any;
  timestamp?: Date;
  ip?: string;
  path?: string;
  method?: string;
  error?: any;
  stack?: string;
  userRole?: string | string[];
  userPermissions?: string[];
  requiredRoles?: string[];
  resource?: string;
  action?: string;
}

export interface LogDocument {
  level: string;
  message: string;
  service: string;
  context?: string;
  userId?: string;
  metadata?: any;
  timestamp: Date;
  expiresAt?: Date;
}

const LOGS_DIR = path.join(process.cwd(), "logs");

if (!fs.existsSync(LOGS_DIR)) {
  fs.mkdirSync(LOGS_DIR, { recursive: true });
}

const dailyRotateTransport = (level: string) =>
  new DailyRotateFile({
    filename: path.join(LOGS_DIR, `%DATE%-${level}.log`),
    datePattern: "YYYY-MM-DD",
    level,
    maxSize: "20m",
    maxFiles: "14d",
    zippedArchive: true,
  });

export const winstonLogger: winston.Logger = winston.createLogger({
  level: LogLevel.DEBUG,
  format: winston.format.combine(
    winston.format.timestamp({ format: "YYYY-MM-DD HH:mm:ss" }),
    winston.format.json()
  ),
  transports: [
    new winston.transports.Console(),
    dailyRotateTransport(LogLevel.ERROR),
    dailyRotateTransport(LogLevel.INFO),
    dailyRotateTransport(LogLevel.HTTP),
    dailyRotateTransport(LogLevel.DEBUG),
  ],
});

export const initializeLogger = async (): Promise<void> => {
  return;
};

class Logger {
  private serviceName: string;

  constructor(serviceName: string) {
    this.serviceName = serviceName;
  }

  error(message: string, options?: LogOptions): void {
    this.log(LogLevel.ERROR, message, options);
  }

  warn(message: string, options?: LogOptions): void {
    this.log(LogLevel.WARN, message, options);
  }

  info(message: string, options?: LogOptions): void {
    this.log(LogLevel.INFO, message, options);
  }

  http(message: string, options?: LogOptions): void {
    this.log(LogLevel.HTTP, message, options);
  }

  debug(message: string, options?: LogOptions): void {
    this.log(LogLevel.DEBUG, message, options);
  }

  private log(level: LogLevel, message: string, options?: LogOptions): void {
    const log: LogDocument = {
      level,
      message,
      service: this.serviceName,
      context: options?.context,
      userId: options?.userId,
      metadata: options?.metadata,
      timestamp: options?.timestamp ?? new Date(),
    };

    winstonLogger.log(log);
  }
}

export const logger = new Logger("App");

export function getLogger(serviceName: string): Logger {
  return new Logger(serviceName);
}
'@

$loggerServiceContent | Set-Content "src/infrastructure/logging/logger.service.ts"

# ============================================
# CONFIG.TS - DINAMICO SEGUN ELECCIONES
# ============================================
Write-Host "Creando src/config.ts..."

$configLines = @(
    "export const config = {",
    "",
    "  initialized: false,",
    "",
    "  environment: process.env.NODE_ENV || `"development`",",
    "  ",
    "  server: {",
    "    port: process.env.PORT || $SERVER_PORT,",
    "  },",
    "",
    "  urls: {",
    "    baseUrl: process.env.FRONTEND_URL || `"http://localhost`",",
    "  },",
    "",
    "  db: {",
    "    repository: process.env.DATABASE_REPOSITORY || `"IN_MEMORY`",",
    "    environment: process.env.DATABASE_ENV || `"local`",",
    "    databaseUrl: `"`",",
    "  },",
    "  ",
    "  jwt: {",
    "    jwtSecret: process.env.JWT_SECRETS || `"`",",
    "    jwtExpiresIn: parseInt(process.env.JWT_EXPIRES_IN) || 0,",
    "  },"
)

if ($USE_SQS) {
    $configLines += @(
        "",
        "  sqsConfig: {",
        "    region: '',",
        "    endpoint: '',",
        "    credentials: {",
        "      accessKeyId: '',",
        "      secretAccessKey: '',",
        "    },",
        "  },"
    )
}

if ($USE_RABBITMQ) {
    $configLines += @(
        "",
        "  rabbitConfig: {",
        "    url: process.env.RABBITMQ_URL || 'amqp://user:password@localhost:5672',",
        "  },"
    )
}

$configLines += @(
    "",
    "  async init() {",
    "    if (this.initialized) return;",
    "    this.initialized = true;",
    "  }",
    "};"
)

$configLines | Set-Content "src/config.ts"

# ============================================
# INTEGRATION EVENT INTERFACE
# ============================================
$integrationEventContent = @'
export interface IntegrationEvent <TPayload = unknown> {
  readonly eventName: string;
  readonly payload: TPayload;
}
'@

$integrationEventContent | Set-Content "src/application/interfaces/integration-event.interface.ts"

# ============================================
# EVENT BUS PORT
# ============================================
$eventBusPortContent = @'
import { Token } from "typedi";
import { IntegrationEvent } from "../interfaces/integration-event.interface";

export interface EventBus {
  publish(events: IntegrationEvent[]): Promise<void>;
}

export const EVENT_BUS_PUBLISHER = new Token<EventBus>("EVENT_BUS_PUBLISHER")
'@

$eventBusPortContent | Set-Content "src/application/ports/event-bus.port.ts"

# ============================================
# ADAPTADORES DE MENSAJERIA
# ============================================
if ($USE_SQS) {
    Write-Host "Creando adaptador SQS..."

    $sqsRoutingContent = @'
export const SQS_EVENT_ROUTING: Record<string, string> = {
  'event': 'http://localhost:4566/000000000000/event',
}
'@

    $sqsRoutingContent | Set-Content "src/infrastructure/messaging/sqs-event.routing.ts"

    $sqsAdapterContent = @'
import { Service } from "typedi";
import { SendMessageCommand, SQSClient } from "@aws-sdk/client-sqs";
import { getLogger } from "../logging/logger.service";
import { config } from "../../config";
import { EVENT_BUS_PUBLISHER, EventBus } from "../../application/ports/event-bus.port";
import { SQS_EVENT_ROUTING } from "../messaging/sqs-event.routing";
import { IntegrationEvent } from "../../application/interfaces/integration-event.interface";

const logger = getLogger("SqsEventPublisherAdapter");

@Service(EVENT_BUS_PUBLISHER)
export class SqsEventPublisherAdapter implements EventBus {
  private readonly sqsClient: SQSClient;

  constructor() {
    this.sqsClient = new SQSClient(config.sqsConfig)
  }

  async publish(events: IntegrationEvent[]): Promise<void> {
    try {
      for (const event of events) {
        const queueUrl = SQS_EVENT_ROUTING[event.eventName];

        if (!queueUrl) {
          throw new Error(`No hay cola configurada para el evento ${event.eventName}`);
        }

        await this.sqsClient.send(
          new SendMessageCommand({
            QueueUrl: queueUrl,
            MessageBody: JSON.stringify({
              eventName: event.eventName,
              ocurredOn: new Date(),
              payload: event.payload
            })
          })
        );
      }
    }
    catch (error) {
      logger.error(`${JSON.stringify(error)}`);
    }
  }
}
'@

    $sqsAdapterContent | Set-Content "src/infrastructure/adapters/sqs.adapter.ts"
}

if ($USE_RABBITMQ) {
    Write-Host "Creando adaptador RabbitMQ..."

    $rabbitAdapterContent = @'
import { Service } from "typedi";
import * as amqp from "amqplib";
import { getLogger } from "../logging/logger.service";
import { config } from "../../config";
import { EVENT_BUS_PUBLISHER, EventBus } from "../../application/ports/event-bus.port";
import { IntegrationEvent } from "../../application/interfaces/integration-event.interface";

const logger = getLogger("RabbitMQEventPublisherAdapter");

@Service(EVENT_BUS_PUBLISHER)
export class RabbitMQEventPublisherAdapter implements EventBus {
  private connection: amqp.Connection | null = null;
  private channel: amqp.Channel | null = null;

  async connect(): Promise<void> {
    try {
      this.connection = await amqp.connect(config.rabbitConfig.url);
      this.channel = await this.connection.createChannel();
      logger.info("Conectado a RabbitMQ");
    } catch (error) {
      logger.error(`Error conectando a RabbitMQ: ${JSON.stringify(error)}`);
      throw error;
    }
  }

  async publish(events: IntegrationEvent[]): Promise<void> {
    try {
      if (!this.channel) {
        await this.connect();
      }

      for (const event of events) {
        const exchange = event.eventName;
        
        await this.channel!.assertExchange(exchange, 'fanout', { durable: true });
        
        const message = JSON.stringify({
          eventName: event.eventName,
          occurredOn: new Date(),
          payload: event.payload
        });

        this.channel!.publish(exchange, '', Buffer.from(message), {
          persistent: true
        });

        logger.info(`Evento publicado: ${event.eventName}`);
      }
    } catch (error) {
      logger.error(`Error publicando eventos: ${JSON.stringify(error)}`);
      throw error;
    }
  }

  async close(): Promise<void> {
    await this.channel?.close();
    await this.connection?.close();
  }
}
'@

    $rabbitAdapterContent | Set-Content "src/infrastructure/adapters/rabbitmq.adapter.ts"
}

# ============================================
# BOOTSTRAP
# ============================================
Write-Host "Creando archivos bootstrap..."

$bootstrapImports = @(
    "// Importar utilidades",
    "import `"../../load-env-vars`";",
    "import `"reflect-metadata`";",
    "",
    "// Registrar adaptadores"
)

if ($USE_SQS) {
    $bootstrapImports += 'import "../adapters/sqs.adapter";'
}

if ($USE_RABBITMQ) {
    $bootstrapImports += 'import "../adapters/rabbitmq.adapter";'
}

$bootstrapImports += @(
    "",
    "// Registrar repositorios (si llegara a aplicar)"
)

$bootstrapImports | Set-Content "src/infrastructure/bootstrap/bootstrap.ts"

# ============================================
# FASTIFY BOOTSTRAP
# ============================================
$fastifyBootstrapContent = @'
import Fastify, { FastifyInstance } from "fastify";
import cors from "@fastify/cors";
import formbody from "@fastify/formbody";
import { healthRouter } from "../http/routes/health.router";
import { getLogger } from "../logging/logger.service";
import { config } from "../../config";

const logger = getLogger("service");

export async function bootstrapFastify(): Promise<FastifyInstance> {
  const app = Fastify({
    logger: false,    
  });

  await app.register(cors, {
    origin: true,
  });

  await app.register(formbody);

  const apiPaths = {
    health: "/api/health",
  };

  await app.register(healthRouter, { prefix: apiPaths.health });
  
  const port = Number(config.server.port);

  try {
    app.listen({ port, host: "0.0.0.0" });
    logger.info(`Running on port ${port}`);
  } catch (err) {
    logger.error("Error starting server", { error: err });
    process.exit(1);
  }

  return app;
}
'@

$fastifyBootstrapContent | Set-Content "src/infrastructure/bootstrap/fastify.bootstrap.ts"

# ============================================
# REPOSITORIES BOOTSTRAP
# ============================================
$repositoriesBootstrapContent = @'
import { Container } from "typedi";
import { config } from "../../config";

export async function bootstrapRepositories() {
  // Descomentar y modificar con los valores correspondientes
  // if (config.db.repository === "PRISMA") {
  //   const { Repository } = await import("../db/repositories/prisma-XXXX.repository");
  //   Container.set(PORT_REPOSITORY, new PrismaXXXRepository());
  // }
}
'@

$repositoriesBootstrapContent | Set-Content "src/infrastructure/bootstrap/repositories.bootstrap.ts"

# ============================================
# SWAGGER SCHEMAS
# ============================================
$baseResponseSchemaContent = @'
export const baseResponseSchema = {
  $id: "baseResponse",
  type: "object",
  properties: {
    request: { type: "string", enum: ["controllerName::functionName()"] },
    response: { type: "string", enum: ["OK"] },
    success: { type: "boolean" },
    message: { type: "string" },
    data: {}
  },
  required: ["request", "response", "success", "message"]
};
'@

$baseResponseSchemaContent | Set-Content "src/infrastructure/swagger/schemas/baseResponseSchema.ts"

$errorResponseSchemaContent = @'
export const errorResponseSchema = {
  $id: "errorResponse",
  type: "object",
  properties: {
    request: { type: "string" },
    response: { type: "string", enum: ["KO"] },
    message: { type: "string" },
  },
  required: ["request", "response", "message"],
};
'@

$errorResponseSchemaContent | Set-Content "src/infrastructure/swagger/schemas/errorResponseSchema.ts"

# ============================================
# SWAGGER CONFIG
# ============================================
$swaggerContent = @"
import { FastifyInstance } from "fastify";
import fastifySwagger from "@fastify/swagger";
import fastifySwaggerUI from "@fastify/swagger-ui";

import { config } from "../../config";
import { baseResponseSchema } from "./schemas/baseResponseSchema";
import { errorResponseSchema } from "./schemas/errorResponseSchema";

export async function registerSwagger(app: FastifyInstance) {
  if (config.environment !== "development") {
    return;
  }

  app.addSchema(baseResponseSchema);
  app.addSchema(errorResponseSchema);

  await app.register(fastifySwagger, {
    openapi: {
      info: {
        title: "$PROJECT_NAME",
        version: "1.0.0",
      },
    },
  });

  await app.register(fastifySwaggerUI, {
    routePrefix: "/api/docs",
  });

  console.log("Swagger habilitado en /api/docs");
}
"@

$swaggerContent | Set-Content "src/infrastructure/swagger/swagger.ts"

# ============================================
# INDEX.TS
# ============================================
$indexContent = @'
import "./infrastructure/bootstrap/bootstrap";

import { config } from "./config";
import { bootstrapFastify } from "./infrastructure/bootstrap/fastify.bootstrap";

async function bootstrap() {
  await config.init();
  bootstrapFastify();
}

bootstrap();
'@

$indexContent | Set-Content "src/index.ts"

# ============================================
# CONTROLLERS
# ============================================
$healthControllerContent = @'
import { FastifyReply, FastifyRequest } from "fastify";

class HealthController {
  async run(_req: FastifyRequest, res: FastifyReply) {
    res.status(200).send("It Works!");
  }
}

export default new HealthController();
'@

$healthControllerContent | Set-Content "src/infrastructure/http/controllers/health.controller.ts"

$baseControllerContent = @'
import { FastifyReply } from "fastify";
import { getLogger } from "../../logging/logger.service";

const logger = getLogger("base-controller");

export abstract class BaseController {
  protected async handleHttpResponse(res: FastifyReply, controller: string, functionName: string, callback: () => Promise<any>) {
    try {
      const result = await callback();

      return res.status(200).send({
        request: `${controller}::${functionName}`,
        response: 'OK',
        success: result.success,
        message: result.message,
        data: result.data,
      });
    } catch (error) {
      logger.error(`Error en ${controller}::${functionName}`);
      return res.status(400).send({
        request: `${controller}::${functionName}`,
        response: 'KO',
        message: String(error),
      });
    }
  }
}
'@

$baseControllerContent | Set-Content "src/infrastructure/http/controllers/base.controller.ts"

# ============================================
# ROUTES
# ============================================
$healthRouterContent = @'
import { FastifyInstance } from "fastify";
import healthController from "../controllers/health.controller";

export async function healthRouter(fastify: FastifyInstance) {
  fastify.get("/", healthController.run);
}
'@

$healthRouterContent | Set-Content "src/infrastructure/http/routes/health.router.ts"

# ============================================
# EDITOR CONFIG - DINAMICO
# ============================================
$editorconfigContent = @"
root = true
[*]
indent_style = $INDENT_STYLE
indent_size = $INDENT_SIZE
end_of_line = lf
insert_final_newline = true
"@

$editorconfigContent | Set-Content ".editorconfig"

# ============================================
# ESLINT CONFIG
# ============================================
$eslintConfigContent = @'
module.exports = {
  plugins: ['simple-import-sort'],
  rules: {
    'simple-import-sort/imports': [
      'error',
      {
        groups: [
          // Node.js built-ins
          [
            '^node:',
            '^(fs|path|crypto|http|https|stream|util|events|os)(/|$)',
          ],

          // Dependencias externas (npm)
          [
            '^@?\\w',
          ],

          // typedi (si lo queres separado explicitamente)
          [
            '^typedi$',
          ],

          // Infraestructura
          [
            '^@/infrastructure(/.*|$)',
          ],

          // Application
          [
            '^@/application(/.*|$)',
          ],

          // Domain
          [
            '^@/domain(/.*|$)',
          ],

          // Imports relativos
          [
            '^\\.\\.(?!/?$)',
            '^\\.\\./?$',
            '^\\./(?=.*/)(?!/?$)',
            '^\\.(?!/?$)',
            '^\\./?$',
          ],
        ],
      },
    ],
  },
};
'@

$eslintConfigContent | Set-Content "eslint.config.js"

# ============================================
# GITIGNORE
# ============================================
$gitignoreContent = @'
node_modules
dist
.env*
npm-debug.log*
coverage
*.log
logs/
'@

$gitignoreContent | Set-Content ".gitignore"

# ============================================
# DOCKERFILE - DINAMICO
# ============================================
$dockerfileContent = @"
# ============ Base Build Stage ============
FROM node:18-alpine AS builder

WORKDIR /app

ARG NODE_ENV=production
ENV NODE_ENV=`${NODE_ENV}

COPY package*.json ./
RUN npm install

COPY . .
RUN npm run build

# ============ Runtime Stage ============
FROM node:18-alpine AS runner

WORKDIR /app

ARG NODE_ENV=production
ENV NODE_ENV=`${NODE_ENV}

COPY package*.json ./
RUN npm install --only=production

COPY --from=builder /app/dist ./dist
COPY env.`${NODE_ENV} .env

EXPOSE $SERVER_PORT

CMD [\"npm\", \"start\"]
"@

$dockerfileContent | Set-Content "Dockerfile"

# ============================================
# DOCKER COMPOSE - DINAMICO
# ============================================
$composeLines = @(
    "version: `"3.9`"",
    "",
    "services:",
    "  api:",
    "    build:",
    "      context: .",
    "      dockerfile: Dockerfile",
    "      args:",
    "        NODE_ENV: `${NODE_ENV:-development}",
    "    container_name: `${PROJECT_NAME:-ddd-app}",
    "    restart: always",
    "    ports:",
    "      - ''$SERVER_PORT':$SERVER_PORT'",
    "    depends_on:"
)

if ($USE_SQLSERVER) { $composeLines += "      - sqlserver" }
if ($USE_MYSQL) { $composeLines += "      - mysql" }
if ($USE_POSTGRES) { $composeLines += "      - postgres" }
if ($USE_MONGODB) { $composeLines += "      - mongodb" }
if ($USE_RABBITMQ) { $composeLines += "      - rabbitmq" }

$composeLines += @(
    "    environment:",
    "      - NODE_ENV=`${NODE_ENV:-development}",
    "    volumes:",
    "      - .:/app",
    "      - /app/node_modules",
    ""
)

if ($USE_SQLSERVER) {
    $composeLines += @(
        "  sqlserver:",
        "    image: mcr.microsoft.com/mssql/server:2019-latest",
        "    container_name: sqlserver",
        "    environment:",
        '      ACCEPT_EULA: "Y"',
        '      SA_PASSWORD: "YourStrong@Passw0rd"',
        "    ports:",
        '      - "1433:1433"',
        "    volumes:",
        "      - sql_data:/var/opt/mssql",
        ""
    )
}

if ($USE_MYSQL) {
    $composeLines += @(
        "  mysql:",
        "    image: mysql:8",
        "    container_name: mysql",
        "    environment:",
        "      MYSQL_ROOT_PASSWORD: root",
        "      MYSQL_DATABASE: mydb",
        "    ports:",
        '      - "3306:3306"',
        "    volumes:",
        "      - mysql_data:/var/lib/mysql",
        ""
    )
}

if ($USE_POSTGRES) {
    $composeLines += @(
        "  postgres:",
        "    image: postgres:15",
        "    container_name: postgres",
        "    environment:",
        "      POSTGRES_USER: postgres",
        "      POSTGRES_PASSWORD: postgres",
        "      POSTGRES_DB: mydb",
        "    ports:",
        '      - "5432:5432"',
        "    volumes:",
        "      - postgres_data:/var/lib/postgresql/data",
        ""
    )
}

if ($USE_MONGODB) {
    $composeLines += @(
        "  mongodb:",
        "    image: mongo:6",
        "    container_name: mongodb",
        "    environment:",
        "      MONGO_INITDB_ROOT_USERNAME: root",
        "      MONGO_INITDB_ROOT_PASSWORD: root",
        "    ports:",
        '      - "27017:27017"',
        "    volumes:",
        "      - mongo_data:/data/db",
        ""
    )
}

if ($USE_RABBITMQ) {
    $composeLines += @(
        "  rabbitmq:",
        "    image: rabbitmq:3-management",
        "    container_name: rabbitmq",
        "    ports:",
        '      - "5672:5672"',
        '      - "15672:15672"',
        "    volumes:",
        "      - rabbitmq_data:/var/lib/rabbitmq",
        ""
    )
}

$composeLines += "volumes:"

if ($USE_SQLSERVER) { $composeLines += "  sql_data:" }
if ($USE_MYSQL) { $composeLines += "  mysql_data:" }
if ($USE_POSTGRES) { $composeLines += "  postgres_data:" }
if ($USE_MONGODB) { $composeLines += "  mongo_data:" }
if ($USE_RABBITMQ) { $composeLines += "  rabbitmq_data:" }

$composeLines | Set-Content "docker-compose.yml"

# ============================================
# TEST DUMMY
# ============================================
$dummyTestContent = @'
console.log("Dummy test ok!");
'@

$dummyTestContent | Set-Content "test/dummy.test.js"

# ============================================
# GIT + HUSKY
# ============================================
Write-Host "Inicializando Git + Husky..."
git init > $null 2>&1
git add .
git commit -m "Commit inicial" > $null 2>&1

npx husky init > $null 2>&1
"npx lint-staged" | Set-Content ".husky/pre-commit"

$lintstagedrcContent = @'
{
  "src/**/*.{js,ts}": [
    "eslint --fix"
  ]
}
'@

$lintstagedrcContent | Set-Content ".lintstagedrc.json"

$huskyGitignoreContent = @'
*
'@

$huskyGitignoreContent | Set-Content ".husky/.gitignore"

git add .lintstagedrc.json package.json .husky
git commit -m "Configuracion de husky" > $null 2>&1

Write-Host "Creando ramas para flujo de trabajo..."
git branch dev 2>$null
git branch uat 2>$null
git branch prod 2>$null
git checkout dev > $null 2>&1

# ============================================
# RESUMEN FINAL
# ============================================
Write-Host ""
Write-Host "============================================"
Write-Host "Proyecto generado correctamente"
Write-Host "============================================"
Write-Host ""
Write-Host "Configuracion:"
Write-Host "  - Proyecto: $PROJECT_NAME"
Write-Host "  - Autor: $AUTHOR_NAME"
Write-Host "  - Puerto: $SERVER_PORT"
Write-Host ""
Write-Host "Bases de datos:"
if ($USE_SQLSERVER) { Write-Host "  * SQL Server" }
if ($USE_MYSQL) { Write-Host "  * MySQL" }
if ($USE_POSTGRES) { Write-Host "  * PostgreSQL" }
if ($USE_MONGODB) { Write-Host "  * MongoDB" }
if ($USE_SQLITE) { Write-Host "  * SQLite" }
Write-Host ""
Write-Host "Mensajeria:"
if ($USE_SQS) { Write-Host "  * AWS SQS" }
if ($USE_RABBITMQ) { Write-Host "  * RabbitMQ" }
Write-Host ""
Write-Host "Editor:"
Write-Host "  - Indent Style: $INDENT_STYLE"
Write-Host "  - Indent Size: $INDENT_SIZE"
Write-Host ""
Write-Host "Para comenzar:"
Write-Host "   cd $PROJECT_NAME"
Write-Host "   npm run dev"
Write-Host ""
Write-Host "============================================"
