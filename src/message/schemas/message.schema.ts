import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument } from 'mongoose';

export type MessageDocument = HydratedDocument<Message>;

@Schema({ collection: 'messages' })
export class Message {
  @Prop({ required: true })
  type: string;

  // @Prop({ type: [{ type: mongoose.Schema.Types.ObjectId, ref: 'User' }] })
  // user: User;

  @Prop({ required: true })
  message: string;

  @Prop()
  deviceId?: string;

  @Prop({ required: true, select: false })
  receivedAt?: Date;
}

export const MessageSchema = SchemaFactory.createForClass(Message);
