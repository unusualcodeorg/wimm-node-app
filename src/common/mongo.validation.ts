import {
  registerDecorator,
  ValidationArguments,
  ValidationOptions,
} from 'class-validator';
import { Types } from 'mongoose';

export function IsMongoIdObject(validationOptions?: ValidationOptions) {
  return function (object: object, propertyName: string) {
    registerDecorator({
      name: 'IsMongoIdObject',
      target: object.constructor,
      propertyName: propertyName,
      constraints: [],
      options: validationOptions,
      validator: {
        validate(value: any) {
          return Types.ObjectId.isValid(value);
        },

        defaultMessage(validationArguments?: ValidationArguments) {
          const property = validationArguments?.property ?? '';
          return `${property} should be a valid MongoId`;
        },
      },
    });
  };
}
