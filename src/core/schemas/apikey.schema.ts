import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument, Types } from 'mongoose';

export enum Permission {
  GENERAL = 'GENERAL', // All api end points are allowed
  XYZ_SERVICE = 'XYZ_SERVICE',
}

export type MessageDocument = HydratedDocument<ApiKey>;

@Schema({ collection: 'api_keys', versionKey: false, timestamps: true })
export class ApiKey {
  readonly _id: Types.ObjectId;

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

  @Prop({ default: true })
  readonly status: boolean;
}

export const ApiKeySchema = SchemaFactory.createForClass(ApiKey);

ApiKeySchema.index({ key: 1, status: 1 });
