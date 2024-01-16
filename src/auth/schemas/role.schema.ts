import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument, Types } from 'mongoose';

export type RoleDocument = HydratedDocument<Role>;

export enum RoleCode {
  VIEWER = 'VIEWER',
  ADMIN = 'ADMIN',
  MANAGER = 'MANAGER',
}

@Schema({ collection: 'roles', versionKey: false, timestamps: true })
export class Role {
  readonly _id: Types.ObjectId;

  @Prop({
    type: String,
    required: true,
    unique: true,
    enum: Object.values(RoleCode),
  })
  readonly code: RoleCode;

  @Prop({ default: true })
  readonly status: boolean;
}

export const RoleSchema = SchemaFactory.createForClass(Role);

RoleSchema.index({ code: 1, status: 1 });
