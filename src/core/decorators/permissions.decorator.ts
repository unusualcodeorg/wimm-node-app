import { Reflector } from '@nestjs/core';
import { Permission } from '../schemas/apikey.schema';

/**
 * API KEY permission
 */
export const Permissions = Reflector.createDecorator<Permission[]>();
