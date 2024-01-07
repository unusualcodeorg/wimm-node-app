import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument } from 'mongoose';

export type MessageDocument = HydratedDocument<User>;

@Schema({ collection: 'users', versionKey: false, timestamps: true })
export class User {
  @Prop({ trim: true, maxlength: 200 })
  name?: string;

  @Prop({ select: false, trim: true, maxlength: 200 })
  deviceId?: string;

  @Prop({ unique: true, required: true, trim: true })
  email: string;

  @Prop({ select: false, required: true, trim: true })
  password?: string;

  @Prop({ select: false, trim: true, maxlength: 2000 })
  firebaseFcmToken?: string;

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

  // roles: Role[];

  @Prop({ default: false })
  verified: boolean;

  @Prop({ default: true, select: false })
  readonly status?: boolean;
}

export const UserSchema = SchemaFactory.createForClass(User);

UserSchema.index({ _id: 1, status: 1 });
UserSchema.index({ email: 1, status: 1 });
