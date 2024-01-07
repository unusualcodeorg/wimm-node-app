import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import mongoose, { HydratedDocument, Types } from 'mongoose';
import { User } from '../../user/schemas/user.schema';

export type MessageDocument = HydratedDocument<Message>;

@Schema({ collection: 'messages', versionKey: false, timestamps: true })
export class Message {
  readonly _id: Types.ObjectId;

  @Prop({ required: true })
  type: string;

  @Prop({
    type: mongoose.Schema.Types.ObjectId,
    ref: User.name,
    required: true,
  })
  user: User;

  @Prop({ required: true })
  message: string;

  @Prop()
  deviceId?: string;
}

export const MessageSchema = SchemaFactory.createForClass(Message);
