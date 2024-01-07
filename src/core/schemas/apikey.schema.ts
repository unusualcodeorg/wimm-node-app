import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument } from 'mongoose';

export enum Permission {
  GENERAL = 'GENERAL',
}

export type MessageDocument = HydratedDocument<ApiKey>;

@Schema({ collection: 'api_keys', versionKey: false, timestamps: true })
export class ApiKey {
  @Prop({ trim: true, required: true, unique: true, maxlength: 1024 })
  readonly key: string;

  @Prop({ required: true, min: 1, max: 100 })
  readonly version: number;

  @Prop({
    type: [{ type: String, required: true, enum: Object.values(Permission) }],
    required: true,
  })
  readonly permissions: Permission[];

  @Prop({
    type: [{ type: String, required: true, trim: true, maxlength: 1000 }],
    required: true,
  })
  readonly comments: string[];

  @Prop({ default: true, select: false })
  readonly status?: boolean;
}

export const ApiKeySchema = SchemaFactory.createForClass(ApiKey);

ApiKeySchema.index({ key: 1, status: 1 });
