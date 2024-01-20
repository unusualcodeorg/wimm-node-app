import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import mongoose, { HydratedDocument, Types } from 'mongoose';
import { Role } from '../../auth/schemas/role.schema';

export type MessageDocument = HydratedDocument<User>;

@Schema({ collection: 'users', versionKey: false, timestamps: true })
export class User {
  readonly _id: Types.ObjectId;

  @Prop({ trim: true, maxlength: 200 })
  name?: string;

  @Prop({ select: false, trim: true, maxlength: 200 })
  deviceId?: string;

  @Prop({ unique: true, required: true, trim: true, select: false })
  email: string;

  @Prop({
    select: false,
    required: true,
    trim: true,
    minlength: 6,
    maxlength: 100,
  })
  password?: string;

  @Prop({ select: false, trim: true, maxlength: 2000 })
  firebaseToken?: string;

  @Prop({ select: false, trim: true, maxlength: 200 })
  googleId?: string;

  @Prop({ select: false, trim: true, maxlength: 200 })
  facebookId?: string;

  @Prop({ trim: true, maxlength: 500 })
  profilePicUrl?: string;

  @Prop({ trim: true, maxlength: 500 })
  googleProfilePicUrl?: string;

  @Prop({ trim: true, maxlength: 500 })
  facebookProfilePicUrl?: string;

  @Prop({ trim: true, maxlength: 500 })
  tagline?: string;

  @Prop({ type: [{ type: mongoose.Schema.Types.ObjectId, ref: Role.name }] })
  roles: Role[];

  @Prop({ default: false })
  verified: boolean;

  @Prop({ default: true })
  readonly status: boolean;
}

export const UserSchema = SchemaFactory.createForClass(User);

UserSchema.index({ _id: 1, status: 1 });
UserSchema.index({ email: 1, status: 1 });
