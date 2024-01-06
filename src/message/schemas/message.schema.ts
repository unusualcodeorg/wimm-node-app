import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument } from 'mongoose';

export type MessageDocument = HydratedDocument<Message>;

@Schema({ collection: 'messages', versionKey: false, timestamps: true })
export class Message {
  @Prop({ required: true })
  type: string;

  // @Prop({ type: [{ type: mongoose.Schema.Types.ObjectId, ref: 'User' }] })
  // user: User;

  @Prop({ required: true })
  message: string;

  @Prop()
  deviceId?: string;
}

export const MessageSchema = SchemaFactory.createForClass(Message);
