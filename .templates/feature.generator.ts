import { existsSync } from 'fs';
import { mkdir, writeFile } from 'fs/promises';
import { join } from 'path';

async function generateFeature(featureTemplate: string) {
  if (!featureTemplate || typeof featureTemplate !== 'string')
    return console.log('feature name should be non empty string');

  const featureName = featureTemplate.toLowerCase();
  const featureDir = join(__dirname, '../src', featureName);
  const exists = existsSync(featureDir);
  if (exists) return console.log(featureName, 'already exists');

  await mkdir(featureDir);

  await generateDto(featureDir, featureName);
  await generateSchemas(featureDir, featureName);
  await generateService(featureDir, featureName);
  await generateController(featureDir, featureName);
  await generateModule(featureDir, featureName);
}

async function generateModule(featureDir: string, featureName: string) {
  const featureLower = featureName.toLowerCase();
  const featureCaps = capitalizeFirstLetter(featureName);
  const modulePath = join(featureDir, `${featureLower}.module.ts`);

  const template = `import { Module } from '@nestjs/common';
import { ${featureCaps}, ${featureCaps}Schema } from './schemas/${featureLower}.schema';
import { MongooseModule } from '@nestjs/mongoose';
import { ${featureCaps}Controller } from './${featureLower}.controller';
import { ${featureCaps}Service } from './${featureLower}.service';

@Module({
  imports: [
    MongooseModule.forFeature([{ name: ${featureCaps}.name, schema: ${featureCaps}Schema }]),
  ],
  controllers: [${featureCaps}Controller],
  providers: [${featureCaps}Service],
  exports: [${featureCaps}Service],
})
export class ${featureCaps}Module {}
`;

  await writeFile(modulePath, template);
}

async function generateService(featureDir: string, featureName: string) {
  const featureLower = featureName.toLowerCase();
  const featureCaps = capitalizeFirstLetter(featureName);
  const servicePath = join(featureDir, `${featureLower}.service.ts`);

  const template = `import { Injectable } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model } from 'mongoose';
import { ${featureCaps} } from './schemas/${featureLower}.schema';
import { Create${featureCaps}Dto } from './dto/create-${featureLower}.dto';
import { User } from '../user/schemas/user.schema';

@Injectable()
export class ${featureCaps}Service {
  constructor(
    @InjectModel(${featureCaps}.name) private readonly ${featureLower}Model: Model<${featureCaps}>,
  ) {}

  async create(user: User, create${featureCaps}Dto: Create${featureCaps}Dto): Promise<${featureCaps}> {
    const ${featureLower} = await this.${featureLower}Model.create({
      ...create${featureCaps}Dto,
      user: user,
    });
    return ${featureLower};
  }
}
`;
  await writeFile(servicePath, template);
}

async function generateController(featureDir: string, featureName: string) {
  const featureLower = featureName.toLowerCase();
  const featureCaps = capitalizeFirstLetter(featureName);
  const controlerPath = join(featureDir, `${featureLower}.controller.ts`);

  const template = `import { Body, Controller, Post, Request } from '@nestjs/common';
import { ${featureCaps}Service } from './${featureLower}.service';
import { Create${featureCaps}Dto } from './dto/create-${featureLower}.dto';
import { ProtectedRequest } from '../core/http/request';

@Controller('${featureLower}')
export class ${featureCaps}Controller {
  constructor(private readonly ${featureLower}Service: ${featureCaps}Service) {}

  @Post()
  async create(
    @Request() request: ProtectedRequest,
    @Body() create${featureCaps}Dto: Create${featureCaps}Dto,
  ) {
    await this.${featureLower}Service.create(request.user, create${featureCaps}Dto);
    return 'success';
  }
}
`;
  await writeFile(controlerPath, template);
}

async function generateSchemas(featureDir: string, featureName: string) {
  const schemasDirPath = join(featureDir, 'schemas');
  await mkdir(schemasDirPath);

  const featureLower = featureName.toLowerCase();
  const featureCaps = capitalizeFirstLetter(featureName);
  const schemaPath = join(featureDir, `schemas/${featureLower}.schema.ts`);

  const template = `import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import mongoose, { HydratedDocument, Types } from 'mongoose';
import { User } from '../../user/schemas/user.schema';

export type ${featureCaps}Document = HydratedDocument<${featureCaps}>;

@Schema({ collection: '${featureLower}s', versionKey: false, timestamps: true })
export class ${featureCaps} {
  readonly _id: Types.ObjectId;

  @Prop({ required: true })
  type: string;

  @Prop({
    type: mongoose.Schema.Types.ObjectId,
    ref: User.name,
    required: true,
  })
  user: User;

  @Prop({ default: true })
  status: boolean;
}

export const ${featureCaps}Schema = SchemaFactory.createForClass(${featureCaps});
`;
  await writeFile(schemaPath, template);
}

async function generateDto(featureDir: string, featureName: string) {
  const dtoDirPath = join(featureDir, 'dto');
  await mkdir(dtoDirPath);

  const featureLower = featureName.toLowerCase();
  const featureCaps = capitalizeFirstLetter(featureName);
  const dtoPath = join(featureDir, `dto/create-${featureLower}.dto.ts`);

  const template = `import { IsNotEmpty, MaxLength } from 'class-validator';

export class Create${featureCaps}Dto {
  @IsNotEmpty()
  readonly property1: string;

  @IsNotEmpty()
  @MaxLength(1000)
  readonly property2: string;
}
`;
  await writeFile(dtoPath, template);
}

function capitalizeFirstLetter(str: string) {
  return str.charAt(0).toUpperCase() + str.slice(1);
}

async function main() {
  const featureName = process.argv[2];
  generateFeature(featureName);
}

main();
